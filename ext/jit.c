#define _GNU_SOURCE
#include "stdio.h"

#include "jit/jit.h"
#include "jit/jit-dump.h"
#include "ruby.h"

static VALUE rb_mJIT;
static VALUE rb_cContext;
static VALUE rb_cFunction;
static VALUE rb_cType;
static VALUE rb_mABI;
static VALUE rb_cValue;
static VALUE rb_cLabel;
static VALUE rb_mCall;

static jit_type_t jit_type_VALUE;
static jit_type_t jit_type_ID;
static jit_type_t jit_type_CSTRING;
static jit_type_t jit_type_CLONG;

static jit_type_t ruby_vararg_signature;

/* TODO: There's no good way once we create a closure to know when we're
 * done with it.  This is to keep the function around as long as the
 * closure is -- which is necessary to prevent the app from crashing --
 * but the result is that the function is permanently around, since it
 * is never removed from this array */
static VALUE libjit_closure_functions;

/* TODO: this might not be right for 64-bit systems */
typedef jit_uint jit_VALUE;
#define jit_underlying_type_VALUE jit_type_uint
#define SET_CONSTANT_VALUE(c, v) c.un.uint_value = v;
typedef jit_uint jit_ID;
#define jit_underlying_type_ID jit_type_uint
#define SET_CONSTANT_ID(c, v) c.un.uint_value = v;
#define jit_underlying_type_CLONG jit_type_int

/* TODO: Need better (more consistent) names for these */
enum User_Defined_Tag
{
  OBJECT_TAG,
  ID_TAG,
  CSTRING_TAG,
  CLONG_TAG,
  RUBY_VARARG_SIGNATURE_TAG,
};

/* TODO: Need better (more consistent) names for these */
enum Meta_Tag
{
  VALUE_OBJECTS,
  FUNCTIONS,
  CONTEXT,
  TAG_FOR_SIGNATURE,
};

static void check_type(char const * param_name, VALUE expected_klass, VALUE val)
{
  if(CLASS_OF(val) != expected_klass)
  {
    rb_raise(
        rb_eTypeError,
        "Wrong type for %s; expected %s but got %s",
        param_name,
        rb_class2name(expected_klass),
        rb_class2name(CLASS_OF(val)));
  }
}

/* ---------------------------------------------------------------------------
 * Context
 * ---------------------------------------------------------------------------
 */

static void context_mark(jit_context_t context)
{
  VALUE functions = (VALUE)jit_context_get_meta(context, FUNCTIONS);
  rb_gc_mark(functions);
}

static VALUE context_s_new(VALUE klass)
{
  jit_context_t context = jit_context_create();
  jit_context_set_meta(context, FUNCTIONS, (void*)rb_ary_new(), 0);
  return Data_Wrap_Struct(rb_cContext, context_mark, jit_context_destroy, context);
}

static VALUE context_build(VALUE self)
{
  jit_context_t context;
  Data_Get_Struct(self, struct _jit_context, context);
  jit_context_build_start(context);
  return rb_ensure(rb_yield, self, RUBY_METHOD_FUNC(jit_context_build_end), (VALUE)context);
}

static VALUE context_s_build(VALUE klass)
{
  return context_build(context_s_new(klass));
}

/* ---------------------------------------------------------------------------
 * Function
 * ---------------------------------------------------------------------------
 */

static void mark_function(jit_function_t function)
{
  rb_gc_mark((VALUE)jit_function_get_meta(function, VALUE_OBJECTS));
  rb_gc_mark((VALUE)jit_function_get_meta(function, CONTEXT));
}

static VALUE create_function(int argc, VALUE * argv, VALUE klass)
{
  VALUE context;
  VALUE signature;
  VALUE parent;
  jit_function_t function;
  jit_function_t parent_function;
  jit_context_t jit_context;
  jit_type_t jit_signature;
  jit_type_t jit_real_signature;
  VALUE function_obj;
  VALUE functions;
  int signature_tag;

  rb_scan_args(argc, argv, "21", &context, &signature, &parent);

  Data_Get_Struct(context, struct _jit_context, jit_context);
  Data_Get_Struct(signature, struct _jit_type, jit_signature);

  signature_tag = jit_type_get_kind(jit_signature);

  if((jit_real_signature = jit_type_get_tagged_type(jit_signature)))
  {
    jit_signature = jit_real_signature;
  }

  if(RTEST(parent))
  {
    Data_Get_Struct(parent, struct _jit_function, parent_function);
    function = jit_function_create_nested(jit_context, jit_signature, parent_function);
  }
  else
  {
    function = jit_function_create(jit_context, jit_signature);
  }

  /* Make sure the function is around as long as the context is */
  if(!jit_function_set_meta(function, VALUE_OBJECTS, (void *)rb_ary_new(), 0, 0))
  {
    rb_raise(rb_eNoMemError, "Out of memory");
  }

  /* Remember the signature's tag for later */
  if(!jit_function_set_meta(function, TAG_FOR_SIGNATURE, (void *)signature_tag, 0, 0))
  {
    rb_raise(rb_eNoMemError, "Out of memory");
  }

  if(!jit_function_set_meta(function, CONTEXT, (void *)context, 0, 0))
  {
    rb_raise(rb_eNoMemError, "Out of memory");
  }

  function_obj = Data_Wrap_Struct(rb_cFunction, mark_function, 0, function);

  functions = (VALUE)jit_context_get_meta(jit_context, FUNCTIONS);
  rb_ary_push(functions, function_obj);

  return function_obj;
}

static VALUE function_compile(VALUE self)
{
  jit_function_t function;
  Data_Get_Struct(self, struct _jit_function, function);
  if(!jit_function_compile(function))
  {
    rb_raise(rb_eRuntimeError, "Unable to compile function");
  }
  return self;
}

static VALUE function_s_new(int argc, VALUE * argv, VALUE klass)
{
  if(rb_block_given_p())
  {
    rb_raise(rb_eArgError, "Function.new does not take a block");
  }

  return create_function(argc, argv, klass);
}

/* TODO: call jit_function_abandon if an exception occurs during
 * compilation */
static VALUE function_s_compile(int argc, VALUE * argv, VALUE klass)
{
  VALUE function = create_function(argc, argv, klass);
  rb_yield(function);
  function_compile(function);
  return function;
}

static VALUE function_get_param(VALUE self, VALUE idx)
{
  jit_function_t function;
  jit_value_t v;
  Data_Get_Struct(self, struct _jit_function, function);
  v = jit_value_get_param(function, NUM2INT(idx));
  return Data_Wrap_Struct(rb_cValue, 0, 0, v);
}

#include "insns.inc"

static VALUE function_insn_call(int argc, VALUE * argv, VALUE self)
{
  jit_function_t function;

  VALUE name;
  VALUE called_function;
  VALUE args;
  VALUE flags = Qnil;

  char const * j_name;
  jit_function_t j_called_function;
  jit_value_t * j_args;
  jit_value_t retval;
  int j_flags;

  int j;

  rb_scan_args(argc, argv, "3*", &name, &called_function, &flags, &args);

  Data_Get_Struct(self, struct _jit_function, function);
  j_name = STR2CSTR(name);
  check_type("called function", rb_cFunction, called_function);
  Data_Get_Struct(called_function, struct _jit_function, j_called_function);
  j_args = ALLOCA_N(jit_value_t, RARRAY(args)->len);

  for(j = 0; j < RARRAY(args)->len; ++j)
  {
    jit_value_t arg;
    Data_Get_Struct(RARRAY(args)->ptr[j], struct _jit_value, arg);
    if(!arg)
    {
      rb_raise(rb_eArgError, "Argument %d is invalid", j);
    }
    j_args[j] = arg;
  }
  j_flags = NUM2INT(flags);

  retval = jit_insn_call(
      function, j_name, j_called_function, 0, j_args, RARRAY(args)->len, j_flags);
  return Data_Wrap_Struct(rb_cValue, 0, 0, retval);
}

static VALUE function_insn_call_native(int argc, VALUE * argv, VALUE self)
{
  jit_function_t function;

  VALUE name;
  VALUE args;
  VALUE flags = Qnil;

  char const * j_name;
  jit_value_t * j_args;
  jit_value_t retval;
  int j_flags;

  int j;

  jit_type_t signature;
  void * native_func = 0;

  rb_scan_args(argc, argv, "2*", &name, &flags, &args);

  Data_Get_Struct(self, struct _jit_function, function);
  j_name = rb_id2name(SYM2ID(name));

  j_args = ALLOCA_N(jit_value_t, RARRAY(args)->len);

  for(j = 0; j < RARRAY(args)->len; ++j)
  {
    jit_value_t arg;
    Data_Get_Struct(RARRAY(args)->ptr[j], struct _jit_value, arg);
    if(!arg)
    {
      rb_raise(rb_eArgError, "Argument %d is invalid", j);
    }
    j_args[j] = arg;
  }
  j_flags = NUM2INT(flags);

  if(SYM2ID(name) == rb_intern("rb_funcall"))
  {
    /* TODO: what to do about exceptions? */
    /* TODO: validate num args? */

    VALUE sprintf_args[] = {
        rb_str_new2("%s(%s)"),
        name,
        ID2SYM(jit_value_get_nint_constant(j_args[1])),
    };
    name = rb_f_sprintf(sizeof(sprintf_args)/sizeof(sprintf_args[0]), sprintf_args);
    j_name = STR2CSTR(name);

    native_func = (void *)rb_funcall;

    jit_type_t * param_types = ALLOCA_N(jit_type_t, RARRAY(args)->len);
    param_types[0] = jit_type_VALUE;
    param_types[1] = jit_type_ID;
    param_types[2] = jit_type_int;

    for(j = 0; j < RARRAY(args)->len; ++j)
    {
      param_types[j] = jit_type_VALUE;
    }

    signature = jit_type_create_signature(
        jit_abi_cdecl, /* TODO: vararg? */
        jit_type_VALUE,
        param_types,
        RARRAY(args)->len,
        1);
  }
  else if(SYM2ID(name) == rb_intern("rb_funcall2"))
  {
    /* TODO: what to do about exceptions? */
    /* TODO: validate num args? */

    VALUE sprintf_args[] = {
        rb_str_new2("%s(%s)"),
        name,
        ID2SYM(jit_value_get_nint_constant(j_args[1])),
    };

    name = rb_f_sprintf(sizeof(sprintf_args)/sizeof(sprintf_args[0]), sprintf_args);
    j_name = STR2CSTR(name);
    native_func = (void *)rb_funcall2;
    jit_type_t param_types[] = { jit_type_VALUE, jit_type_ID, jit_type_int, jit_type_void_ptr };
    signature = jit_type_create_signature(
        jit_abi_cdecl, /* TODO: vararg? */
        jit_type_VALUE,
        param_types,
        RARRAY(args)->len,
        1);
  }
  else if(SYM2ID(name) == rb_intern("rb_funcall3"))
  {
    /* TODO: what to do about exceptions? */
    /* TODO: validate num args? */

    VALUE sprintf_args[] = {
        rb_str_new2("%s(%s)"),
        name,
        ID2SYM(jit_value_get_nint_constant(j_args[1])),
    };

    name = rb_f_sprintf(sizeof(sprintf_args)/sizeof(sprintf_args[0]), sprintf_args);
    j_name = STR2CSTR(name);
    native_func = (void *)rb_funcall3;
    jit_type_t param_types[] = { jit_type_VALUE, jit_type_ID, jit_type_int, jit_type_void_ptr };
    signature = jit_type_create_signature(
        jit_abi_cdecl, /* TODO: vararg? */
        jit_type_VALUE,
        param_types,
        RARRAY(args)->len,
        1);
  }
  else if(SYM2ID(name) == rb_intern("rb_iterate"))
  {
    native_func = (void *)rb_iterate;
    jit_type_t param_types[] = { jit_type_void_ptr, jit_type_void_ptr, jit_type_void_ptr, jit_type_void_ptr };
    signature = jit_type_create_signature(
        jit_abi_cdecl,
        jit_type_VALUE,
        param_types,
        4,
        1);
  }
  else if(SYM2ID(name) == rb_intern("rb_const_get"))
  {
    native_func = (void *)rb_const_get;
    jit_type_t param_types[] = { jit_type_VALUE, jit_type_ID };
    signature = jit_type_create_signature(
        jit_abi_cdecl,
        jit_type_VALUE,
        param_types,
        2,
        1);
  }
  else if(SYM2ID(name) == rb_intern("rb_class_of"))
  {
    native_func = (void *)rb_class_of;
    jit_type_t param_types[] = { jit_type_VALUE };
    signature = jit_type_create_signature(
        jit_abi_cdecl,
        jit_type_VALUE,
        param_types,
        1,
        1);
  }
  else if(SYM2ID(name) == rb_intern("rb_str_dup"))
  {
    native_func = (void *)rb_str_dup;
    jit_type_t param_types[] = { jit_type_VALUE };
    signature = jit_type_create_signature(
        jit_abi_cdecl,
        jit_type_VALUE,
        param_types,
        1,
        1);
  }
  else if(SYM2ID(name) == rb_intern("rb_str_concat"))
  {
    native_func = (void *)rb_str_concat;
    jit_type_t param_types[] = { jit_type_VALUE, jit_type_VALUE };
    signature = jit_type_create_signature(
        jit_abi_cdecl,
        jit_type_VALUE,
        param_types,
        2,
        1);
  }
  else if(SYM2ID(name) == rb_intern("rb_range_new"))
  {
    native_func = (void *)rb_range_new;
    jit_type_t param_types[] = { jit_type_VALUE, jit_type_VALUE, jit_type_int };
    signature = jit_type_create_signature(
        jit_abi_cdecl,
        jit_type_VALUE,
        param_types,
        3,
        1);
  }
  else if(SYM2ID(name) == rb_intern("rb_ary_new2"))
  {
    native_func = (void *)rb_ary_new2;
    jit_type_t param_types[] = { jit_type_int };
    signature = jit_type_create_signature(
        jit_abi_cdecl,
        jit_type_VALUE,
        param_types,
        1,
        1);
  }
  else if(SYM2ID(name) == rb_intern("rb_ary_store"))
  {
    native_func = (void *)rb_ary_store;
    jit_type_t param_types[] = { jit_type_VALUE, jit_type_int, jit_type_VALUE };
    signature = jit_type_create_signature(
        jit_abi_cdecl,
        jit_type_VALUE,
        param_types,
        3,
        1);
  }
  else if(SYM2ID(name) == rb_intern("rb_ary_entry"))
  {
    native_func = (void *)rb_ary_entry;
    jit_type_t param_types[] = { jit_type_VALUE, jit_type_int };
    signature = jit_type_create_signature(
        jit_abi_cdecl,
        jit_type_VALUE,
        param_types,
        2,
        1);
  }
  else if(SYM2ID(name) == rb_intern("rb_ary_to_ary"))
  {
    native_func = (void *)rb_ary_to_ary;
    jit_type_t param_types[] = { jit_type_VALUE };
    signature = jit_type_create_signature(
        jit_abi_cdecl,
        jit_type_VALUE,
        param_types,
        1,
        1);
  }
  else if(SYM2ID(name) == rb_intern("rb_hash_new"))
  {
    native_func = (void *)rb_hash_new;
    jit_type_t param_types[] = { };
    signature = jit_type_create_signature(
        jit_abi_cdecl,
        jit_type_VALUE,
        param_types,
        0,
        1);
  }
  else if(SYM2ID(name) == rb_intern("rb_hash_aset"))
  {
    native_func = (void *)rb_hash_aset;
    jit_type_t param_types[] = { jit_type_VALUE, jit_type_VALUE, jit_type_VALUE };
    signature = jit_type_create_signature(
        jit_abi_cdecl,
        jit_type_VALUE,
        param_types,
        3,
        1);
  }
  else if(SYM2ID(name) == rb_intern("rb_hash_aref"))
  {
    native_func = (void *)rb_hash_aref;
    jit_type_t param_types[] = { jit_type_VALUE, jit_type_VALUE };
    signature = jit_type_create_signature(
        jit_abi_cdecl,
        jit_type_VALUE,
        param_types,
        2,
        1);
  }
  else if(SYM2ID(name) == rb_intern("rb_uint2inum"))
  {
    native_func = (void *)rb_uint2inum;
    jit_type_t param_types[] = { jit_type_uint };
    signature = jit_type_create_signature(
        jit_abi_cdecl,
        jit_type_VALUE,
        param_types,
        1,
        1);
  }
  else if(SYM2ID(name) == rb_intern("rb_ivar_get"))
  {
    native_func = (void *)rb_ivar_get;
    jit_type_t param_types[] = { jit_type_VALUE, jit_type_ID };
    signature = jit_type_create_signature(
        jit_abi_cdecl,
        jit_type_VALUE,
        param_types,
        2,
        1);
  }
  else
  {
    rb_raise(rb_eArgError, "Invalid native function %s", j_name);
  }

  /* TODO: the signature could be leaked if this function raises an
   * exception */
  retval = jit_insn_call_native(
      function, j_name, native_func, signature, j_args, RARRAY(args)->len, j_flags);
  return Data_Wrap_Struct(rb_cValue, 0, 0, retval);
}

static VALUE function_apply(int argc, VALUE * argv, VALUE self)
{
  jit_function_t function;
  jit_type_t signature;
  int j, n;
  void * * args;
  char * arg_data;

  Data_Get_Struct(self, struct _jit_function, function);
  signature = jit_function_get_signature(function);
  n = jit_type_num_params(signature);

  /* void pointers to each of the arguments */
  args = ALLOCA_N(void *, n);

  /* the actual data */
  /* TODO: we need to allocate the proper size (but 8 bytes per arg
   * should be sufficient for now) */
  arg_data = (char *)ALLOCA_N(char, 8 * n);

  {
    int signature_tag = (int)jit_function_get_meta(function, TAG_FOR_SIGNATURE);
    if(signature_tag == JIT_TYPE_FIRST_TAGGED + RUBY_VARARG_SIGNATURE_TAG)
    {
      /* TODO: validate the number of args passed in (should be at least
       * 1) */
      jit_uint result;
      int f_argc = argc - 1;
      VALUE f_self = *(VALUE *)argv;
      VALUE * f_argv = ((VALUE *)argv) + 1;
      void * f_args[3] = { &f_argc, &f_argv, &f_self };
      jit_function_apply(function, f_args, &result);
      return result;
    }
  }

  /* TODO: validate the number of args passed in */
  for(j = 0; j < n; ++j)
  {
    jit_type_t arg_type = jit_type_get_param(signature, j);
    int kind = jit_type_get_kind(arg_type);
    switch(kind)
    {
      case JIT_TYPE_INT:
      {
        *(int *)arg_data = NUM2INT(argv[j]);
        args[j] = (int *)arg_data;
        arg_data += sizeof(int);
        break;
      }

      case JIT_TYPE_FIRST_TAGGED + OBJECT_TAG:
      {
        *(VALUE *)arg_data = argv[j];
        args[j] = (VALUE *)arg_data;
        arg_data += sizeof(VALUE);
        break;
      }

      case JIT_TYPE_FIRST_TAGGED + ID_TAG:
      {
        *(ID *)arg_data = SYM2ID(argv[j]);
        args[j] = (ID *)arg_data;
        arg_data += sizeof(ID);
        break;
      }

      default:
        rb_raise(rb_eTypeError, "Unsupported type %d", kind);
    }
  }

  /* TODO: don't assume that all functions return int */

  {
    jit_type_t return_type = jit_type_get_return(signature);
    int return_kind = jit_type_get_kind(return_type);
    switch(return_kind)
    {
      case JIT_TYPE_INT:
      {
        jit_int result;
        jit_function_apply(function, args, &result);
        return INT2NUM(result);
      }

      case JIT_TYPE_FIRST_TAGGED + OBJECT_TAG:
      {
        jit_uint result;
        jit_function_apply(function, args, &result);
        return result;
      }

      case JIT_TYPE_FIRST_TAGGED + ID_TAG:
      {
        jit_uint result;
        jit_function_apply(function, args, &result);
        return ID2SYM(result);
      }

      default:
        rb_raise(rb_eTypeError, "Unsupported return type %d", return_kind);
    }
  }
}

/* If passed one value, create a value with jit_value_create.
 * If passed two values, create a constant with the given value.
 */
static VALUE function_value(VALUE self, VALUE type)
{
  jit_function_t function;
  jit_type_t j_type;
  jit_value_t v;

  Data_Get_Struct(self, struct _jit_function, function);

  check_type("type", rb_cType, type);
  Data_Get_Struct(type, struct _jit_type, j_type);

  // TODO: When we wrap a value, we should inject a reference to the
  // function in the object, so the function stays around as long as the
  // value does
  v = jit_value_create(function, j_type);
  return Data_Wrap_Struct(rb_cValue, 0, 0, v);
}

static VALUE function_const(VALUE self, VALUE type, VALUE constant)
{
  jit_function_t function;
  jit_type_t j_type;
  jit_value_t v;

  Data_Get_Struct(self, struct _jit_function, function);

  check_type("type", rb_cType, type);
  Data_Get_Struct(type, struct _jit_type, j_type);

  jit_constant_t c;

  int kind = jit_type_get_kind(j_type);
  switch(kind)
  {
    case JIT_TYPE_INT:
    {
      c.type = j_type;
      c.un.int_value = NUM2INT(constant);
      break;
    }

    case JIT_TYPE_PTR:
    {
      c.type = j_type;
      c.un.ptr_value = (void *)NUM2ULONG(constant);
      break;
    }

    case JIT_TYPE_FIRST_TAGGED + OBJECT_TAG:
    {
      VALUE value_objects = (VALUE)jit_function_get_meta(function, VALUE_OBJECTS);

      c.type = j_type;
      SET_CONSTANT_VALUE(c, constant);

      /* Make sure the object gets marked as long as the function is
       * around */
      /* TODO: not exception-safe */
      rb_ary_push(value_objects, constant);
      break;
    }

    case JIT_TYPE_FIRST_TAGGED + ID_TAG:
    {
      c.type = j_type;
      SET_CONSTANT_ID(c, SYM2ID(constant));
      break;
    }

    case JIT_TYPE_FIRST_TAGGED + CSTRING_TAG:
    {
      VALUE value_objects = (VALUE)jit_function_get_meta(function, VALUE_OBJECTS);

      c.type = j_type;
      c.un.ptr_value = STR2CSTR(constant);

      /* Make sure the object gets marked as long as the function is
       * around */
      /* TODO: not exception-safe */
      rb_ary_push(value_objects, constant);
      break;
    }

    default:
      rb_raise(rb_eTypeError, "Unsupported type");
  }

  v = jit_value_create_constant(function, &c);
  return Data_Wrap_Struct(rb_cValue, 0, 0, v);
}

static VALUE function_ruby_sourceline(VALUE self)
{
  jit_type_t ptr_type = jit_type_create_pointer(jit_type_int, 1);
  jit_constant_t c;
  jit_value_t v;
  jit_function_t function;

  Data_Get_Struct(self, struct _jit_function, function);
  c.type = ptr_type;
  c.un.ptr_value = &ruby_sourceline;
  v = jit_value_create_constant(function, &c);

  return Data_Wrap_Struct(rb_cValue, 0, 0, v);
}

static VALUE function_ruby_sourcefile(VALUE self)
{
  jit_type_t ptr_type = jit_type_create_pointer(jit_type_int, 1);
  jit_constant_t c;
  jit_value_t v;
  jit_function_t function;

  Data_Get_Struct(self, struct _jit_function, function);
  c.type = ptr_type;
  c.un.ptr_value = &ruby_sourcefile;
  v = jit_value_create_constant(function, &c);

  return Data_Wrap_Struct(rb_cValue, 0, 0, v);
}

static VALUE function_optimization_level(VALUE self)
{
  jit_function_t function;
  Data_Get_Struct(self, struct _jit_function, function);
  return INT2NUM(jit_function_get_optimization_level(function));
}

static VALUE function_set_optimization_level(VALUE self, VALUE level)
{
  jit_function_t function;
  Data_Get_Struct(self, struct _jit_function, function);
  jit_function_set_optimization_level(function, NUM2INT(level));
  return level;
}

static VALUE function_max_optimization_level(VALUE klass)
{
  return INT2NUM(jit_function_get_max_optimization_level());
}

static VALUE function_to_s(VALUE self)
{
  jit_function_t function;
  char buf[16*1024]; /* TODO: big enough? */
  FILE * fp = fmemopen(buf, sizeof(buf), "w");
  Data_Get_Struct(self, struct _jit_function, function);
  jit_dump_function(fp, function, 0);
  fclose(fp);
  return rb_str_new2(buf);
}

static VALUE function_to_closure(VALUE self)
{
  jit_function_t function;
  Data_Get_Struct(self, struct _jit_function, function);
  void * closure = jit_function_to_closure(function);
  rb_ary_push(libjit_closure_functions, self);
  return ULONG2NUM((unsigned long)closure);
}

static VALUE function_get_context(VALUE self)
{
  jit_function_t function;
  Data_Get_Struct(self, struct _jit_function, function);
  return (VALUE)jit_function_get_meta(function, CONTEXT);
}

static VALUE function_is_compiled(VALUE self)
{
  jit_function_t function;
  Data_Get_Struct(self, struct _jit_function, function);
  return jit_function_is_compiled(function) ? Qtrue : Qfalse;
}

// TODO: Provide offsetof functions for all the basic types (and make
// this function go away)
static VALUE function_ruby_array_length(VALUE self, VALUE array)
{
  jit_function_t function;
  Data_Get_Struct(self, struct _jit_function, function);
  jit_value_t j_array;
  Data_Get_Struct(array, struct _jit_value, j_array);
  jit_value_t length = jit_insn_load_relative(
      function, j_array, offsetof(struct RArray, len), jit_type_CLONG);
  return Data_Wrap_Struct(rb_cValue, 0, 0, length);
}

static VALUE function_ruby_array_ptr(VALUE self, VALUE array)
{
  jit_function_t function;
  Data_Get_Struct(self, struct _jit_function, function);
  jit_value_t j_array;
  Data_Get_Struct(array, struct _jit_value, j_array);
  jit_value_t length = jit_insn_load_relative(
      function, j_array, offsetof(struct RArray, ptr), jit_type_void_ptr);
  return Data_Wrap_Struct(rb_cValue, 0, 0, length);
}

/* ---------------------------------------------------------------------------
 * Type
 * ---------------------------------------------------------------------------
 */

/* This function does not increment the reference count.  It is assumed
 * that the caller will increment the reference count and that the newly
 * wrapped object will take ownership. */
static VALUE wrap_type(jit_type_t type)
{
  return Data_Wrap_Struct(rb_cType, 0, jit_type_free, type);
}

static VALUE type_s_create_signature(
    VALUE klass, VALUE abi, VALUE return_type, VALUE params)
{
  jit_abi_t j_abi = NUM2INT(abi);
  jit_type_t j_return_type;
  jit_type_t * j_params;
  jit_type_t signature;
  int j;
  int len;

  check_type("return type", rb_cType, return_type);

  Data_Get_Struct(return_type, struct _jit_type, j_return_type);

  Check_Type(params, T_ARRAY);
  len = RARRAY(params)->len;
  j_params = ALLOCA_N(jit_type_t, len);
  for(j = 0; j < len; ++j)
  {
    VALUE param = RARRAY(params)->ptr[j];
    check_type("param", rb_cType, param);
    Data_Get_Struct(param, struct _jit_type, j_params[j]);
  }

  signature = jit_type_create_signature(j_abi, j_return_type, j_params, len, 1);
  return wrap_type(signature);
}

static VALUE type_s_create_struct(
    VALUE klass, VALUE fields)
{
  jit_type_t * j_fields;
  jit_type_t j_struct;
  int len;
  int j;

  Check_Type(fields, T_ARRAY);
  len = RARRAY(fields)->len;
  j_fields = ALLOCA_N(jit_type_t, len);
  for(j = 0; j < len; ++j)
  {
    VALUE field = RARRAY(fields)->ptr[j];
    check_type("field", rb_cType, field);
    Data_Get_Struct(field, struct _jit_type, j_fields[j]);
  }

  j_struct = jit_type_create_struct(j_fields, RARRAY(fields)->len, 1);
  return wrap_type(j_struct);
}

static VALUE type_get_offset(VALUE self, VALUE field_index)
{
  int j_field_index = NUM2INT(field_index);
  jit_type_t type;
  Data_Get_Struct(self, struct _jit_type, type);
  return INT2NUM(jit_type_get_offset(type, j_field_index));
}

/* ---------------------------------------------------------------------------
 * Value
 * ---------------------------------------------------------------------------
 */

static VALUE value_to_s(VALUE self)
{
  /* TODO: We shouldn't depend on glibc */
  char buf[1024];
  FILE * fp = fmemopen(buf, sizeof(buf), "w");
  jit_value_t value;
  jit_function_t function;
  Data_Get_Struct(self, struct _jit_value, value);
  function = jit_value_get_function(value);
  jit_dump_value(fp, function, value, 0);
  fclose(fp);
  return rb_str_new2(buf);
}

static VALUE value_inspect(VALUE self)
{
  jit_value_t value;
  jit_type_t type;
  char * cname = rb_obj_classname(self);
  Data_Get_Struct(self, struct _jit_value, value);
  type = jit_value_get_type(value);
  VALUE args[] = {
      rb_str_new2("<%s:0x%x %s ptr=0x%x type=0x%x>"),
      rb_str_new2(cname),
      ULONG2NUM(self),
      value_to_s(self),
      ULONG2NUM((VALUE)value),
      ULONG2NUM((VALUE)type),
  };
  return rb_f_sprintf(sizeof(args)/sizeof(args[0]), args);
}

static VALUE value_is_valid(VALUE self)
{
  jit_value_t value;
  Data_Get_Struct(self, struct _jit_value, value);
  return value != 0;
}

static VALUE value_is_temporary(VALUE self)
{
  jit_value_t value;
  Data_Get_Struct(self, struct _jit_value, value);
  return jit_value_is_temporary(value) ? Qtrue : Qfalse;
}

static VALUE value_is_local(VALUE self)
{
  jit_value_t value;
  Data_Get_Struct(self, struct _jit_value, value);
  return jit_value_is_local(value) ? Qtrue : Qfalse;
}

static VALUE value_is_constant(VALUE self)
{
  jit_value_t value;
  Data_Get_Struct(self, struct _jit_value, value);
  return jit_value_is_constant(value) ? Qtrue : Qfalse;
}

static VALUE value_is_volatile(VALUE self)
{
  jit_value_t value;
  Data_Get_Struct(self, struct _jit_value, value);
  return jit_value_is_volatile(value) ? Qtrue : Qfalse;
}

static VALUE value_set_volatile(VALUE self)
{
  jit_value_t value;
  Data_Get_Struct(self, struct _jit_value, value);
  jit_value_set_volatile(value);
  return Qnil;
}

static VALUE value_is_addressable(VALUE self)
{
  jit_value_t value;
  Data_Get_Struct(self, struct _jit_value, value);
  return jit_value_is_addressable(value) ? Qtrue : Qfalse;
}

static VALUE value_set_addressable(VALUE self)
{
  jit_value_t value;
  Data_Get_Struct(self, struct _jit_value, value);
  jit_value_set_addressable(value);
  return Qnil;
}

static VALUE value_function(VALUE self)
{
  jit_value_t value;
  jit_function_t function;
  Data_Get_Struct(self, struct _jit_value, value);
  function = jit_value_get_function(value);
  return Data_Wrap_Struct(rb_cFunction, mark_function, 0, function);
}

/* ---------------------------------------------------------------------------
 * Label
 * ---------------------------------------------------------------------------
 */

static VALUE label_s_new(VALUE klass)
{
  jit_label_t * label;
  VALUE labelval = Data_Make_Struct(rb_cLabel, jit_label_t, 0, xfree, label);
  *label = jit_label_undefined;
  return labelval;
}

/* ---------------------------------------------------------------------------
 * Module
 * ---------------------------------------------------------------------------
 */

static VALUE module_define_libjit_method(VALUE klass, VALUE name, VALUE function, VALUE arity)
{
  /* TODO: I think that by using a closure here, we have a memory leak
   * if the method is ever redefined. */
  char const * c_name = STR2CSTR(name);
  jit_function_t j_function;
  Data_Get_Struct(function, struct _jit_function, j_function);
  int c_arity = NUM2INT(arity); /* TODO: validate */
  void * closure = jit_function_to_closure(j_function);
  rb_ary_push(libjit_closure_functions, function);
  rb_define_method(klass, c_name, closure, c_arity);
  return Qnil;
}

/* ---------------------------------------------------------------------------
 * Init
 * ---------------------------------------------------------------------------
 */

void Init_jit()
{
  jit_init();

  rb_mJIT = rb_define_module("JIT");

  rb_cContext = rb_define_class_under(rb_mJIT, "Context", rb_cObject);
  rb_define_singleton_method(rb_cContext, "new", context_s_new, 0);
  rb_define_method(rb_cContext, "build", context_build, 0);
  rb_define_singleton_method(rb_cContext, "build", context_s_build, 0);

  rb_cFunction = rb_define_class_under(rb_mJIT, "Function", rb_cObject);
  rb_define_singleton_method(rb_cFunction, "new", function_s_new, -1);
  rb_define_method(rb_cFunction, "compile", function_compile, 0);
  rb_define_singleton_method(rb_cFunction, "compile", function_s_compile, -1);
  rb_define_method(rb_cFunction, "get_param", function_get_param, 1);
  init_insns();
  rb_define_method(rb_cFunction, "insn_call", function_insn_call, -1);
  rb_define_method(rb_cFunction, "insn_call_native", function_insn_call_native, -1);
  rb_define_method(rb_cFunction, "apply", function_apply, -1);
  rb_define_alias(rb_cFunction, "call", "apply");
  rb_define_method(rb_cFunction, "value", function_value, 1);
  rb_define_method(rb_cFunction, "const", function_const, 2);
  rb_define_method(rb_cFunction, "ruby_sourceline", function_ruby_sourceline, 0);
  rb_define_method(rb_cFunction, "ruby_sourcefile", function_ruby_sourcefile, 0);
  rb_define_method(rb_cFunction, "optimization_level", function_optimization_level, 0);
  rb_define_method(rb_cFunction, "optimization_level=", function_set_optimization_level, 1);
  rb_define_singleton_method(rb_cFunction, "max_optimization_level", function_max_optimization_level, 0);
  rb_define_method(rb_cFunction, "to_s", function_to_s, 0);
  rb_define_method(rb_cFunction, "to_closure", function_to_closure, 0);
  rb_define_method(rb_cFunction, "context", function_get_context, 0);
  rb_define_method(rb_cFunction, "compiled?", function_is_compiled, 0);
  rb_define_method(rb_cFunction, "ruby_array_length", function_ruby_array_length, 1);
  rb_define_method(rb_cFunction, "ruby_array_ptr", function_ruby_array_ptr, 1);

  rb_cType = rb_define_class_under(rb_mJIT, "Type", rb_cObject);
  rb_define_singleton_method(rb_cType, "create_signature", type_s_create_signature, 3);
  rb_define_singleton_method(rb_cType, "create_struct", type_s_create_struct, 1);
  rb_define_method(rb_cType, "get_offset", type_get_offset, 1);
  rb_define_const(rb_cType, "VOID", wrap_type(jit_type_void));
  rb_define_const(rb_cType, "SBYTES", wrap_type(jit_type_sbyte));
  rb_define_const(rb_cType, "UBYTE", wrap_type(jit_type_ubyte));
  rb_define_const(rb_cType, "SHORT", wrap_type(jit_type_short));
  rb_define_const(rb_cType, "USHORT", wrap_type(jit_type_ushort));
  rb_define_const(rb_cType, "INT", wrap_type(jit_type_int));
  rb_define_const(rb_cType, "UINT", wrap_type(jit_type_uint));
  rb_define_const(rb_cType, "NINT", wrap_type(jit_type_nint));
  rb_define_const(rb_cType, "NUINT", wrap_type(jit_type_nuint));
  rb_define_const(rb_cType, "LONG", wrap_type(jit_type_long));
  rb_define_const(rb_cType, "ULONG", wrap_type(jit_type_ulong));
  rb_define_const(rb_cType, "FLOAT32", wrap_type(jit_type_float32));
  rb_define_const(rb_cType, "FLOAT64", wrap_type(jit_type_float64));
  rb_define_const(rb_cType, "NFLOAT", wrap_type(jit_type_nfloat));
  rb_define_const(rb_cType, "VOID_PTR", wrap_type(jit_type_void_ptr));

  jit_type_VALUE = jit_type_create_tagged(jit_underlying_type_VALUE, OBJECT_TAG, 0, 0, 1);
  rb_define_const(rb_cType, "OBJECT", wrap_type(jit_type_VALUE));

  jit_type_ID = jit_type_create_tagged(jit_underlying_type_ID, ID_TAG, 0, 0, 1);
  rb_define_const(rb_cType, "ID", wrap_type(jit_type_ID));

  jit_type_CSTRING = jit_type_create_tagged(jit_type_void_ptr, CSTRING_TAG, 0, 0, 1);
  rb_define_const(rb_cType, "CSTRING", wrap_type(jit_type_CSTRING));

  jit_type_CLONG = jit_type_create_tagged(jit_underlying_type_CLONG, CLONG_TAG, 0, 0, 1);
  rb_define_const(rb_cType, "CLONG", wrap_type(jit_type_CLONG));

  {
    jit_type_t ruby_vararg_param_types[] = { jit_type_int, jit_type_void_ptr, jit_type_VALUE };
    jit_type_t ruby_vararg_signature_untagged = jit_type_create_signature(
          jit_abi_cdecl,
          jit_type_VALUE,
          ruby_vararg_param_types,
          3,
          1);
    ruby_vararg_signature = jit_type_create_tagged(ruby_vararg_signature_untagged, RUBY_VARARG_SIGNATURE_TAG, 0, 0, 1);
  }
  rb_define_const(rb_cType, "RUBY_VARARG_SIGNATURE", wrap_type(ruby_vararg_signature));

  rb_mABI = rb_define_module_under(rb_mJIT, "ABI");
  rb_define_const(rb_mABI, "CDECL", INT2NUM(jit_abi_cdecl));
  rb_define_const(rb_mABI, "VARARG", INT2NUM(jit_abi_vararg));
  rb_define_const(rb_mABI, "STDCALL", INT2NUM(jit_abi_stdcall));
  rb_define_const(rb_mABI, "FASTCALL", INT2NUM(jit_abi_fastcall));

  rb_cValue = rb_define_class_under(rb_mJIT, "Value", rb_cObject);
  rb_define_method(rb_cValue, "to_s", value_to_s, 0);
  rb_define_method(rb_cValue, "inspect", value_inspect, 0);
  rb_define_method(rb_cValue, "valid?", value_is_valid, 0);
  rb_define_method(rb_cValue, "temporary?", value_is_temporary, 0);
  rb_define_method(rb_cValue, "local?", value_is_local, 0);
  rb_define_method(rb_cValue, "constant?", value_is_constant, 0);
  rb_define_method(rb_cValue, "volatile?", value_is_volatile, 0);
  rb_define_method(rb_cValue, "volatile=", value_set_volatile, 0);
  rb_define_method(rb_cValue, "addressable?", value_is_addressable, 0);
  rb_define_method(rb_cValue, "addressable=", value_set_addressable, 0);
  rb_define_method(rb_cValue, "function", value_function, 0);

  rb_cLabel = rb_define_class_under(rb_mJIT, "Label", rb_cObject);
  rb_define_singleton_method(rb_cLabel, "new", label_s_new, 0);

  rb_mCall = rb_define_module_under(rb_mJIT, "Call");
  rb_define_const(rb_mCall, "NOTHROW", INT2NUM(JIT_CALL_NOTHROW));
  rb_define_const(rb_mCall, "NORETURN", INT2NUM(JIT_CALL_NORETURN));
  rb_define_const(rb_mCall, "TAIL", INT2NUM(JIT_CALL_TAIL));

  /* VALUE rb_cModule = rb_define_module(); */
  rb_define_method(rb_cModule, "define_libjit_method", module_define_libjit_method, 3);

  libjit_closure_functions = rb_ary_new();
  rb_gc_register_address(&libjit_closure_functions);
}

