#include "lexical_module.h"

VALUE rb_mLexicalModule;

void
Init_lexical_module(void)
{
  rb_mLexicalModule = rb_define_module("LexicalModule");
}
