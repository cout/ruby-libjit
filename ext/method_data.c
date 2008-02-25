#include "method_data.h"

#include <node.h>
#include <env.h>

typedef VALUE (*Method_Func)(ANYARGS);

static NODE * data_memo_node()
{
  return (NODE *)(RBASIC(ruby_frame->prev->last_class)->klass);
}

static Method_Func actual_cfunc()
{
  return data_memo_node()->nd_cfnc;
}

/* Okay to not pop this temporary frame, since it will be popped by the
 * caller
 */
#define FIX_FRAME() \
  struct FRAME _frame = *ruby_frame; \
  _frame.last_class = RCLASS(ruby_frame->last_class)->super; \
  _frame.prev = ruby_frame; \
  ruby_frame = &_frame; \

static VALUE data_wrapper_m1(int argc, VALUE * argv, VALUE self)
{
  VALUE result;
  FIX_FRAME();
  result = (*actual_cfunc())(argc, argv, self);
  return result;
}

static VALUE data_wrapper_0(VALUE self)
{
  VALUE result;
  FIX_FRAME();
  result = (*actual_cfunc())(self);
  return result;
}

static VALUE data_wrapper_1(VALUE self, VALUE arg1)
{
  VALUE result;
  FIX_FRAME();
  result = (*actual_cfunc())(self, arg1);
  return result;
}

static VALUE data_wrapper_2(VALUE self, VALUE arg1, VALUE arg2)
{
  VALUE result;
  FIX_FRAME();
  result = (*actual_cfunc())(self, arg1, arg2);
  return result;
}

static VALUE data_wrapper_3(VALUE self, VALUE arg1, VALUE arg2, VALUE arg3)
{
  VALUE result;
  FIX_FRAME();
  result = (*actual_cfunc())(self, arg1, arg2, arg3);
  return result;
}

static VALUE data_wrapper_4(VALUE self, VALUE arg1, VALUE arg2, VALUE arg3, VALUE arg4)
{
  VALUE result;
  FIX_FRAME();
  result = (*actual_cfunc())(self, arg1, arg2, arg3, arg4);
  return result;
}

static VALUE data_wrapper_5(VALUE self, VALUE arg1, VALUE arg2, VALUE arg3, VALUE arg4, VALUE arg5)
{
  VALUE result;
  FIX_FRAME();
  result = (*actual_cfunc())(self, arg1, arg2, arg3, arg4, arg5);
  return result;
}

/* Define a method and attach data to it.
 *
 * The method looks to ruby like a normal aliased CFUNC, with a modified
 * origin class:
 *
 * NODE_FBDOY
 *   |- (u1) orig - origin class
 *   |  |- basic
 *   |  |  |- flags - origin class flags + FL_SINGLETON
 *   |  |  +- klass - NODE_MEMO
 *   |  |     |- (u1) cfnc - actual C function to call
 *   |  |     |- (u2) rval - stored data
 *   |  |     +- (u3) 0
 *   |  |- iv_tbl - 0
 *   |  |- m_tbl - 0
 *   |  +- super - actual origin class
 *   |- (u2) mid - name of the method
 *   +- (u3) head - NODE_CFUNC
 *      |- cfnc - wrapper function to call
 *      +- argc - function arity
 *
 * When the wrapper function is called, last_class is set to the origin
 * class found in the FBODY node.  So that the method data will be
 * accessible, and so ruby_frame->last_class will point to klass and not
 * to our MEMO node, it duplicates the current frame and sets last_class:
 *
 * ruby_frame
 *   |- last_class - klass
 *   |- prev
 *   |  |- last_class - NODE_MEMO
 *   |  |  |- (u1) cfnc - actual C function to call
 *   |  |  |- (u2) rval - stored data
 *   |  |  +- (u3) 0
 *   |  |- prev - the real previous frame
 *   |  +- ...
 *   +- ...
 *
 * The method data is then accessible via
 * ruby_frame->prev->last_class->rval.
 */
void define_method_with_data(
    VALUE klass, ID id, VALUE (*cfunc)(ANYARGS), int arity, VALUE data)
{
  /* TODO: origin should have #to_s and #inspect methods defined */
#ifdef HAVE_RB_CLASS_BOOT
  VALUE origin = rb_class_boot(klass);
#else
  VALUE origin = rb_class_new(klass);
#endif
  NODE * node;

  VALUE (*data_wrapper)(ANYARGS);
  switch(arity)
  {
    case 0: data_wrapper = data_wrapper_0; break;
    case 1: data_wrapper = data_wrapper_1; break;
    case 2: data_wrapper = data_wrapper_2; break;
    case 3: data_wrapper = data_wrapper_3; break;
    case 4: data_wrapper = data_wrapper_4; break;
    case 5: data_wrapper = data_wrapper_5; break;
    case -1: data_wrapper = data_wrapper_m1; break;
    default: rb_raise(rb_eArgError, "unsupported arity %d", arity);
  }

  FL_SET(origin, FL_SINGLETON);
  node = NEW_FBODY(NEW_CFUNC(data_wrapper, arity), id, origin);
  RBASIC(origin)->klass = (VALUE)NEW_NODE(NODE_MEMO, cfunc, data, 0);
  rb_add_method(klass, id, node, NOEX_PUBLIC);
}

VALUE get_method_data()
{
  return data_memo_node()->nd_rval;
}

