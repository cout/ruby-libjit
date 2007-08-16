#include "jit/jit.h"
#include "ruby.h"

static VALUE rb_mJIT;
static VALUE rb_cContext;
static VALUE rb_cFunction;
static VALUE rb_cType;
static VALUE rb_mABI;
static VALUE rb_cValue;
static VALUE rb_cLabel;
static VALUE rb_mCall;

enum User_Defined_Tag
{
  OBJECT_TAG,
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
static VALUE context_s_new(VALUE klass)
{
  jit_context_t context = jit_context_create();
  VALUE context_obj =
    Data_Wrap_Struct(rb_cContext, 0, jit_context_destroy, context);
  rb_iv_set(context_obj, "@functions", rb_ary_new());
  return context_obj;
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

static VALUE function_s_new(VALUE klass, VALUE context, VALUE signature)
{
  jit_function_t function;
  jit_context_t jit_context;
  jit_type_t jit_signature;
  VALUE function_obj;
  VALUE functions;

  Data_Get_Struct(context, struct _jit_context, jit_context);
  Data_Get_Struct(signature, struct _jit_type, jit_signature);

  function = jit_function_create(jit_context, jit_signature);

  function_obj = Data_Wrap_Struct(rb_cFunction, 0, 0, function);

  /* Make sure the function is around as long as the context is */
  functions = rb_iv_get(context, "@functions");
  rb_ary_push(functions, function_obj);

  rb_iv_set(function_obj, "@value_objects", rb_ary_new());

  return function_obj;
}

static VALUE function_compile(VALUE self)
{
  jit_function_t function;
  Data_Get_Struct(self, struct _jit_function, function);
  jit_function_compile(function);
  return self;
}

static VALUE function_s_compile(VALUE klass, VALUE context, VALUE signature)
{
  VALUE function = function_s_new(klass, context, signature);
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
  jit_type_t j_called_function_signature;
  jit_value_t * j_args;
  jit_value_t retval;
  int j_flags;

  int j;

  rb_scan_args(argc, argv, "3*", &name, &called_function, &flags, &args);

  Data_Get_Struct(self, struct _jit_function, function);
  j_name = STR2CSTR(name);
  check_type("called function", rb_cFunction, called_function);
  Data_Get_Struct(called_function, struct _jit_function, j_called_function);
  j_called_function_signature = jit_function_get_signature(function);
  j_args = ALLOCA_N(jit_value_t, RARRAY(args)->len);

  for(j = 0; j < RARRAY(args)->len; ++j)
  {
    jit_value_t arg;
    Data_Get_Struct(RARRAY(args)->ptr[j], struct _jit_value, arg);
    j_args[j] = arg;
  }
  j_flags = NUM2INT(flags);

  retval = jit_insn_call(
      function, j_name, j_called_function, 0, j_args, RARRAY(args)->len, j_flags);
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
        jit_ulong result;
        jit_function_apply(function, args, &result);
        return result;
      }

      default:
        rb_raise(rb_eTypeError, "Unsupported return type %d", return_kind);
    }
  }
}

/* If passed one value, create a value with jit_value_create.
 * If passed two values, create a constant with the given value.
 */
static VALUE function_value(int argc, VALUE * argv, VALUE self)
{
  VALUE type;
  VALUE constant;

  jit_function_t function;
  jit_type_t j_type;
  jit_value_t v;

  int num_args = rb_scan_args(argc, argv, "11", &type, &constant);

  Data_Get_Struct(self, struct _jit_function, function);

  check_type("type", rb_cType, type);
  Data_Get_Struct(type, struct _jit_type, j_type);

  if(num_args == 1)
  {
    v = jit_value_create(function, j_type);
  }
  else
  {
    int kind = jit_type_get_kind(j_type);
    switch(kind)
    {
      case JIT_TYPE_INT:
      {
        jit_constant_t c;
        c.type = j_type;
        c.un.int_value = NUM2INT(constant);
        v = jit_value_create_constant(function, &c);
        break;
      }

      case JIT_TYPE_FIRST_TAGGED + OBJECT_TAG:
      {
        jit_constant_t c;
        VALUE value_objects = rb_iv_get(self, "@value_objects");

        c.type = j_type;
        c.un.ulong_value = constant;
        v = jit_value_create_constant(function, &c);

        /* Make sure the object gets marked as long as the function is
         * around */
        rb_ary_push(value_objects, constant);
        break;
      }

      default:
        rb_raise(rb_eTypeError, "Unsupported type");
    }
  }

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

/* ---------------------------------------------------------------------------
 * Type
 * ---------------------------------------------------------------------------
 */

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
  for(j = 0; j < RARRAY(params)->len; ++j)
  {
    VALUE param = RARRAY(params)->ptr[j];
    check_type("param", rb_cType, param);
    Data_Get_Struct(param, struct _jit_type, j_params[j]);
  }

  signature = jit_type_create_signature(j_abi, j_return_type, j_params, len, 1);
  return Data_Wrap_Struct(rb_cType, 0, jit_type_free, signature);
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
  rb_define_singleton_method(rb_cFunction, "new", function_s_new, 2);
  rb_define_method(rb_cFunction, "compile", function_compile, 0);
  rb_define_singleton_method(rb_cFunction, "compile", function_s_compile, 2);
  rb_define_method(rb_cFunction, "get_param", function_get_param, 1);
  init_insns();
  rb_define_method(rb_cFunction, "insn_call", function_insn_call, -1);
  rb_define_method(rb_cFunction, "apply", function_apply, -1);
  rb_define_method(rb_cFunction, "value", function_value, -1);
  rb_define_method(rb_cFunction, "optimization_level", function_optimization_level, 0);
  rb_define_method(rb_cFunction, "optimization_level=", function_set_optimization_level, 1);

  rb_cType = rb_define_class_under(rb_mJIT, "Type", rb_cObject);
  rb_define_singleton_method(rb_cType, "create_signature", type_s_create_signature, 3);
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
  rb_define_const(rb_cType, "OBJECT", wrap_type(jit_type_create_tagged(
              jit_type_ulong, OBJECT_TAG, 0, 0, 1)));

  rb_mABI = rb_define_module_under(rb_mJIT, "ABI");
  rb_define_const(rb_mABI, "CDECL", INT2NUM(jit_abi_cdecl));
  rb_define_const(rb_mABI, "VARARG", INT2NUM(jit_abi_vararg));
  rb_define_const(rb_mABI, "STDCALL", INT2NUM(jit_abi_stdcall));
  rb_define_const(rb_mABI, "FASTCALL", INT2NUM(jit_abi_fastcall));

  rb_cValue = rb_define_class_under(rb_mJIT, "Value", rb_cObject);

  rb_cLabel = rb_define_class_under(rb_mJIT, "Label", rb_cObject);
  rb_define_singleton_method(rb_cLabel, "new", label_s_new, 0);

  rb_mCall = rb_define_module_under(rb_mJIT, "Call");
  rb_define_const(rb_mCall, "NOTHROW", INT2NUM(JIT_CALL_NOTHROW));
  rb_define_const(rb_mCall, "NORETURN", INT2NUM(JIT_CALL_NORETURN));
  rb_define_const(rb_mCall, "TAIL", INT2NUM(JIT_CALL_TAIL));
}

