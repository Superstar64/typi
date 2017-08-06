/+
	Copyright (C) 2015-2017  Freddy Angel Cubas "Superstar64"
	This file is part of Typi.

	Typi is free software: you can redistribute it and/or modify
	it under the terms of the GNU General Public License as published by
	the Free Software Foundation version 3 of the License.

	Typi is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.

	You should have received a copy of the GNU General Public License
	along with Typi.  If not, see <http://www.gnu.org/licenses/>.
+/
module semantic;
import std.algorithm : all, any, canFind, each, filter, map, reduce, until;
import std.array : join, array;
import std.bigint : BigInt;
import std.conv : to;
import std.file : read;
import std.meta : AliasSeq;
import std.range : drop, take;

import ast;
import error : error, Position;
import parser;

void processModule(Module mod) {
	semantic1(mod, null);
}

Expression unalias(Expression expression) {
	if (auto unknown = cast(Variable) expression) {
		if (unknown.definition.manifest) {
			return unknown.definition.definition;
		}
	}
	if (auto dot = cast(Dot) expression) {
		if (dot.variable) {
			return dot.variable.unalias;
		}
	}
	return expression;
}

Bool isBool(Expression type) {
	return cast(Bool) type.unalias;
}

Char isChar(Expression type) {
	return cast(Char) type.unalias;
}

Int isInt(Expression type) {
	return cast(Int) type.unalias;
}

UInt isUInt(Expression type) {
	return cast(UInt) type.unalias;
}

Postfix!"(*)" isPointer(Expression type) {
	return cast(Postfix!"(*)") type.unalias;
}

//todo remove these
ArrayIndex isArray(Expression type) {
	if (type.isType && cast(ArrayIndex) type.unalias) {
		return cast(ArrayIndex) type.unalias;
	}
	return null;
}

FCall isFunction(Expression type) {
	if (type.isType && cast(FCall) type.unalias) {
		return cast(FCall) type.unalias;
	}
	return null;
}

bool isExtern(Expression expression) {
	if (auto ext = cast(Cast) expression.unalias) {
		return !!cast(ExternJS) ext.value;
	}
	return !!cast(ExternJS) expression;
}

ref Expression[] values(Struct stru) {
	auto tuple = cast(TupleLit) stru.value.unalias;
	assert(tuple);
	return tuple.values;
}

ref size_t[string] names(Struct stru) {
	auto tuple = cast(TupleLit) stru.value.unalias;
	assert(tuple);
	return tuple.names;
}

bool isType(Expression expression) {
	expression = expression.unalias;
	return !!cast(Metaclass) expression.type;
}

bool isRuntimeValue(Expression expression) {
	expression = expression.unalias;
	return !(expression.isType || cast(Import) expression);
}

void checkRuntimeValue(Expression expression) {
	if (!isRuntimeValue(expression)) {
		error("Expected runtime value", expression.pos);
	}
}

//makes sure expression is a type or implicitly convert it to a type
void checkType(ref Expression expression) {
	if (auto tuple = cast(TupleLit) expression.unalias) {
		auto structWrap = new Struct;
		structWrap.value = expression;
		expression = structWrap;
		expression.type = metaclass;
	}
	if (!isType(expression)) {
		error("Expected type", expression.pos);
	}
}

Expression createType(T, Args...)(Args args) {
	auto type = createTypeImpl!T(args);
	semantic1Head(type);
	return type;
}

T createTypeImpl(T)()
		if (is(T == Bool) || is(T == Char) || is(T == ImportType) || is(T == ExternType)) {
	auto type = new T;
	semantic1Head(type);
	return type;
}

T createTypeImpl(T)(int size) if (is(T == Int) || is(T == UInt)) {
	auto type = new T;
	type.size = size;
	semantic1Head(type);
	return type;
}

T createTypeImpl(T)(Expression value) if (is(T == Postfix!"(*)")) {
	auto type = new T;
	type.value = value;
	semantic1Head(type);
	return type;
}

T createTypeImpl(T)(Expression[] values = null, size_t[string] names = null)
		if (is(T == Struct)) {
	auto type = new T;
	auto tuple = new TupleLit();
	tuple.values = values;
	tuple.names = names;
	semantic1Head(tuple);
	type.value = tuple;
	semantic1Head(type);
	return type;
}

T createTypeImpl(T)(Expression fptr, Expression arg) if (is(T == FCall)) {
	auto type = new T;
	type.fptr = fptr;
	type.arg = arg;
	semantic1Head(type);
	return type;
}

T createTypeImpl(T)(Expression array) if (is(T == ArrayIndex)) {
	auto type = new T;
	type.array = array;
	type.index = createType!Struct();
	semantic1Head(type);
	return type;
}

//used in semantic1 and creating types
//process certain expressions with out recursing
void semantic1Head(T)(T that) {
	semantic1HeadImpl(that);
	that.type = metaclass;
	that.ispure = true;
	that.process = true;
}

void semantic1Head(TupleLit that) {
	with (that) {
		if (values.map!(a => !!cast(Metaclass) a.unalias).all) {
			auto cycle = new Struct();
			cycle.value = that;
			semantic1Head(cycle);
			type = cycle;
		} else {
			type = createType!Struct(values.map!(a => a.type).array, names);
		}
		ispure = values.map!(a => a.ispure).all;
	}
}

void semantic1HeadImpl(T)(T that)
		if (is(T == Bool) || is(T == Char) || is(T == ImportType) || is(T == ExternType)) {
}

void semantic1HeadImpl(T)(T that) if (is(T == Int) || is(T == UInt)) {
	with (that) {
		if (size == 0) {
			return;
		}
		uint check = 1;
		while (true) {
			if (check == size) {
				return;
			}
			if (check > size) {
				error("Bad Int Size", pos);
			}
			check *= 2;
		}
	}
}

void semantic1HeadImpl(T)(T that) if (is(T == Postfix!"(*)")) {
	with (that) {
		checkType(value);
	}
}

void semantic1HeadImpl(T)(T that) if (is(T == Struct)) {
	with (that) {
		if (!cast(TupleLit) value.unalias) {
			error("expected tuple lit after struct", pos);
		}
		that.values.each!checkType;
	}
}

void semantic1HeadImpl(T)(T that) if (is(T == FCall)) {
	with (that) {
		checkType(fptr);
		checkType(arg);
	}
}

void semantic1HeadImpl(T)(T that) if (is(T == ArrayIndex)) {
	with (that) {
		checkType(index);
		if (!sameType(index, createType!Struct())) {
			error("Expected empty type in array type", pos);
		}
	}
}

void semantic1(Node that, Trace* trace) {
	if (that.process) {
		error("Cyclic variable", that.pos);
	}
	that.process = true;
	auto nextTrace = Trace(that, trace);
	trace = &nextTrace;
	dispatch!(semantic1Impl, Metaclass, Bool, Char, Int, UInt, Postfix!"(*)",
			ModuleVar, Module, Import, IntLit, CharLit, BoolLit, Struct, TupleLit,
			Variable, FuncArgument, If, While, New, NewArray, Cast, Dot, ArrayIndex,
			FCall, Slice, ScopeVar, Scope, FuncLit, StringLit, ArrayLit, ExternJS,
			Binary!"*", Binary!"/", Binary!"%", Binary!"+", Binary!"-",
			Binary!"~", Binary!"==", Binary!"!=", Binary!"<=", Binary!">=",
			Binary!"<", Binary!">", Binary!"&&", Binary!"||", Assign,
			Prefix!"+", Prefix!"-", Prefix!"*", Prefix!"/", Prefix!"&", Prefix!"!")(that, trace);
	if (auto expr = cast(Expression) that) {
		assert(expr.type);
		assert(expr.type.isType);
	}
}

void semantic1Impl(Module that, Trace* trace) {
	with (that) {
		foreach (symbol; symbols) {
			if (!symbol.process) {
				semantic1(symbol, trace);
			}
			if (!symbol.ispure) {
				error("Impure expression in global", symbol.pos);
			}
		}
	}
}

Metaclass metaclass;
static this() {
	metaclass = new Metaclass();
	metaclass.type = metaclass;
	metaclass.ispure = true;
}

void semantic1Impl(Metaclass that, Trace* trace) {
}

void semantic1Impl(Import that, Trace* trace) {
	that.type = createType!ImportType;
	that.ispure = true;
}

void semantic1Impl(T)(T that, Trace* trace)
		if (is(T == Bool) || is(T == Char) || is(T == Int) || is(T == UInt)) {
	semantic1Head(that);
}

void semantic1Impl(T)(T that, Trace* trace) if (is(T == Postfix!"(*)")) {
	with (that) {
		semantic1(value, trace);
		semantic1Head(that);
	}
}

void semantic1Var(Var that, Trace* trace) {
	with (that) {
		semantic1(definition, trace);
		ispure = definition.ispure;
		if (!that.manifest) {
			ispure = false;
			checkRuntimeValue(definition);
		}
		if (explicitType) {
			semantic1(explicitType, trace);
			checkType(explicitType);
			if (!sameTypeValueType(definition, explicitType)) {
				error("types don't match", pos);
			}
		}
	}
}

void semantic1Impl(ModuleVar that, Trace* trace) {
	with (that) {
		semantic1Var(that, trace);
	}
}

void semantic1Impl(IntLit that, Trace* trace) {
	with (that) {
		if (usigned) {
			type = createType!UInt(0);
		} else {
			type = createType!Int(0);
		}
		ispure = true;
	}
}

void semantic1Impl(CharLit that, Trace* trace) {
	with (that) {
		type = createType!Char;
		ispure = true;
	}
}

void semantic1Impl(BoolLit that, Trace* trace) {
	with (that) {
		type = createType!Bool;
		ispure = true;
	}
}

void semantic1Impl(Struct that, Trace* trace) {
	with (that) {
		semantic1(value, trace);
		semantic1Head(that);
	}
}

void semantic1Impl(TupleLit that, Trace* trace) {
	with (that) {
		foreach (value; values) {
			semantic1(value, trace);
		}

		semantic1Head(that);
	}
}

void semantic1Impl(Variable that, Trace* trace) {
	with (that) {
		Trace subTrace;
		auto source = trace.search(name, subTrace);
		if (source is null) {
			error("Unknown variable", pos);
		}
		definition = source;
		processVariable(that, &subTrace);
		checkNotClosure(that, trace, pos);
	}
}

void processVariable(Variable that, Trace* definitionTrace) {
	with (that) {
		if (definition.type is null) {
			semantic1(definition, definitionTrace);
		}
		assert(definition.type);

		if (definition.manifest) {
			type = that.unalias.type;
			lvalue = that.unalias.lvalue;
			ispure = that.unalias.ispure;
		} else {
			type = definition.type;
			lvalue = true;
			ispure = !!cast(ScopeVar) definition.definition;
		}
	}
}

void checkNotClosure(Variable that, Trace* trace, Position pos) {
	auto definition = cast(ScopeVar) that.definition;
	if (!definition) {
		return;
	}
	if (definition.manifest) {
		if (auto sub = cast(Variable) definition.definition) {
			checkNotClosure(sub, trace, pos); //unalias
		}
	} else {
		auto funcRange = trace.range.map!(a => a.node)
			.map!(a => cast(FuncLit) a).filter!(a => !!a);
		if (funcRange.empty) {
			assert(0); //this should never happen
		}
		if (funcRange.front !is definition.func) {
			error("Closures not supported", pos);
		}
	}
}

void semantic1Impl(FuncArgument that, Trace* trace) {
	foreach (node; trace.range.map!(a => a.node)) {
		if (auto func = cast(FuncLit) node) {
			that.func = func;
			that.type = func.argument;
			//todo make lvalue-able
			return;
		}
	}
	error("$@ without function", that.pos);
}

void semantic1Impl(If that, Trace* trace) {
	with (that) {
		semantic1(cond, trace);
		semantic1(yes, trace);
		semantic1(no, trace);
		if (!cond.type.isBool) {
			error("Boolean expected in if expression", cond.pos);
		}
		if (!sameTypeValueValue(yes, no)) {
			error("If expression with the true and false parts having different types", pos);
		}
		type = yes.type;
		ispure = cond.ispure && yes.ispure && no.ispure;
	}
}

void semantic1Impl(While that, Trace* trace) {
	with (that) {
		semantic1(cond, trace);
		semantic1(state, trace);
		if (!cond.type.isBool) {
			error("Boolean expected in while expression", cond.pos);
		}
		type = createType!Struct();
		ispure = cond.ispure && state.ispure;
	}
}

void semantic1Impl(New that, Trace* trace) {
	with (that) {
		semantic1(value, trace);
		type = createType!(Postfix!"(*)")(value.type);
		ispure = value.ispure;
	}
}

void semantic1Impl(NewArray that, Trace* trace) {
	with (that) {
		semantic1(length, trace);
		semantic1(value, trace);
		if (!sameTypeValueType(length, createType!UInt(0))) {
			error("Can only create an array with length of UInts", length.pos);
		}
		type = createType!ArrayIndex(value.type);
		ispure = length.ispure && value.ispure;
	}
}

void semantic1Impl(Cast that, Trace* trace) {
	with (that) {
		semantic1(value, trace);
		semantic1(wanted, trace);
		checkType(wanted);
		if (!castable(value.type, wanted)) {
			error("Unable to cast", pos);
		}
		type = wanted;
		ispure = value.ispure;
	}
}

void semantic1Impl(Dot that, Trace* trace) {
	with (that) {
		semantic1(value, trace);
		semantic1Dot(value.type, trace, that);
		ispure = value.ispure;
	}
}

void semantic1Dot(Expression that, Trace* trace, Dot dot) {
	dispatch!(semantic1DotImpl, Struct, ArrayIndex, ImportType, Expression)(
			that.unalias, trace, dot);
}

void semantic1DotImpl(T)(T that, Trace* trace, Dot dot) {
	auto nextTrace = Trace(that, trace);
	trace = &nextTrace;
	with (that) {
		static if (is(T == Struct)) {
			auto index = dot.index;
			if (index.peek!string) {
				auto str = index.get!string;
				if (!(str in that.names)) {
					error("Unable to find field", dot.pos);
				}
				dot.type = that.values[that.names[str]];
			} else {
				uint typeIndex = index.get!(BigInt).toInt;
				if (typeIndex >= that.values.length) {
					error("Index number to high", dot.pos);
				}
				dot.type = that.values[typeIndex];
			}
			dot.lvalue = dot.value.lvalue;
		} else static if (is(T == ArrayIndex)) {
			auto index = dot.index;
			if (!(index.peek!string && index.get!string == "length")) {
				semantic1DotImpl!Expression(that, trace, dot);
				return;
			}
			dot.type = createType!UInt(0);
		} else static if (is(T == ImportType)) {
			if (dot.index.peek!BigInt) {
				error("attempting to index a module with an integer", pos);
			}
			auto imp = cast(Import) dot.value.unalias;
			auto name = dot.index.get!string;
			if (!(name in imp.mod.symbols)) {
				error(name ~ " doesn't exist in module", dot.pos);
			}
			auto definition = imp.mod.symbols[name];
			if (!definition.visible) {
				error(name ~ " is not visible", dot.pos);
			}
			dot.variable = new Variable();
			dot.variable.name = name;
			dot.variable.definition = definition;
			auto definitionTrace = Trace(imp.mod, null);
			processVariable(dot.variable, &definitionTrace);
			dot.type = dot.variable.type;
			dot.lvalue = dot.variable.lvalue;
			dot.ispure = dot.variable.ispure;
		} else static if (is(T == Expression)) {
			error("Unable to dot", pos);
		} else {
			pragma(msg, T);
			static assert(0);
		}
	}
}

void semantic1Impl(ArrayIndex that, Trace* trace) {
	with (that) {
		semantic1(array, trace);
		semantic1(index, trace);
		if (array.isType) {
			semantic1Head(that);
		} else {
			if (!array.type.isArray) {
				error("Unable able to index", pos);
			}
			if (!sameTypeValueType(index, createType!UInt(0))) {
				error("Can only index an array with UInts", pos);
			}
			auto arrayType = array.type.isArray;
			type = arrayType.array;
			lvalue = true;
			ispure = array.ispure && index.ispure;
		}
	}
}

void semantic1Impl(FCall that, Trace* trace) {
	with (that) {
		semantic1(fptr, trace);
		semantic1(arg, trace);
		if (fptr.isType || arg.isType) {
			semantic1Head(that);
		} else {
			auto fun = fptr.type.isFunction;
			if (!fun) {
				import std.stdio;

				writeln(fptr.type.isType);
				error("Not a function", pos);
			}
			if (!sameTypeValueType(arg, fun.arg)) {
				error("Unable to call function with the  argument's type", pos);
			}
			type = fun.fptr;
			ispure = fptr.ispure && arg.ispure /* todo fix me && fun.ispure*/ ;
		}
	}
}

void semantic1Impl(Slice that, Trace* trace) {
	with (that) {
		semantic1(array, trace);
		semantic1(left, trace);
		semantic1(right, trace);
		if (!array.type.isArray) {
			error("Not an array", pos);
		}
		if (!(sameTypeValueType(right, createType!UInt(0))
				&& sameTypeValueType(left, createType!UInt(0)))) {
			error("Can only index an array with UInts", pos);
		}
		type = array.type;
		ispure = array.ispure && left.ispure && right.ispure;
	}
}

void semantic1Impl(string op)(Binary!op that, Trace* trace) {
	with (that) {
		semantic1(left, trace);
		semantic1(right, trace);
		static if (["*", "/", "%", "+", "-", "<=", ">=", ">", "<"].canFind(op)) {
			auto ty = left.type;
			if (!((ty.isUInt || ty.isInt) && (sameTypeValueValue(left, right)))) {
				error(op ~ " only works on Ints or UInts of the same Type", pos);
			}
			static if (["<=", ">=", ">", "<"].canFind(op)) {
				type = createType!Bool;
			} else {
				type = ty;
			}
			ispure = left.ispure && right.ispure;
		} else static if (op == "~") {
			auto ty = left.type;
			if (!ty.isArray && sameType(ty, right.type)) {
				error("~ only works on Arrays of the same Type", pos);
			}
			type = ty;
			ispure = left.ispure && right.ispure;
		} else static if (["==", "!="].canFind(op)) {
			if (!(sameTypeValueValue(left, right))) {
				error(op ~ " only works on the same Type", pos);
			}
			type = createType!Bool;
			ispure = left.ispure && right.ispure;
		} else static if (["&&", "||"].canFind(op)) {
			auto ty = left.type;
			if (!(ty.isBool && sameType(ty, right.type))) {
				error(op ~ " only works on Bools", pos);
			}
			type = createType!Bool;
			ispure = left.ispure && right.ispure;
		} else {
			static assert(0);
		}
	}
}

void semantic1Impl(Assign that, Trace* trace) {
	with (that) {
		semantic1(left, trace);
		semantic1(right, trace);
		if (!(sameType(left.type, right.type) || implicitConvert(right, left.type))) {
			error("= only works on the same type", pos);
		}
		if (!left.lvalue) {
			error("= only works on lvalues", pos);
		}
		ispure = left.ispure && right.ispure;
	}
}

void semantic1Impl(string op)(Prefix!op that, Trace* trace) {
	with (that) {
		semantic1(value, trace);
		static if (op == "-") {
			if (!value.type.isInt) {
				error("= only works Signed Ints", pos);
			}
			type = value.type;
			ispure = value.ispure;
		} else static if (op == "*") {
			if (!value.type.isPointer) {
				error("* only works on pointers", pos);
			}
			type = value.type.isPointer.value;
			lvalue = true;
			ispure = value.ispure;
		} else static if (op == "&") {
			if (!value.lvalue) {
				error("& only works lvalues", pos);
			}

			static void assignHeapImpl(T)(T that, Trace* trace) {
				auto nextTrace = Trace(that, trace);
				trace = &nextTrace;
				static if (is(T == Variable)) {

					that.definition.heap = true;
				} else static if (is(T == Dot)) {
					assignHeap(that.value, trace);
				}
			}

			static void assignHeap(Node that, Trace* trace) {
				return dispatch!(assignHeapImpl, Variable, Dot, Node)(that, trace);
			}

			assignHeap(value, trace);

			type = createType!(Postfix!"(*)")(value.type);
			ispure = value.ispure;
		} else static if (op == "!") {
			if (!value.type.isBool) {
				error("! only works on Bools", pos);
			}
			type = value.type;
			ispure = value.ispure;
		} else static if (["+", "/"].canFind(op)) {
			error(op ~ " not supported", pos);
		} else {
			static assert(0);
		}
	}
}

void semantic1Impl(ScopeVar that, Trace* trace) {
	with (that) {
		semantic1Var(that, trace);
		if (!manifest) {
			auto funcRange = trace.range.map!(a => a.node)
				.map!(a => cast(FuncLit) a).filter!(a => !!a);
			if (funcRange.empty) {
				assert(0);
			}
			func = funcRange.front;
		}
	}
}

void semantic1Impl(Scope that, Trace* trace) {
	with (that) {
		ispure = true;
		foreach (symbol; symbols) {
			semantic1(symbol, trace);
		}
		foreach (state; states) {
			semantic1(state, trace);
			trace.context.pass(state);
			ispure = ispure && state.ispure;
		}
		if (last is null) {
			last = new TupleLit();
		}
		semantic1(last, trace);
		type = last.type;
	}
}

void semantic1Impl(FuncLit that, Trace* trace) {
	with (that) {
		semantic1(argument, trace);
		checkType(argument);

		if (explict_return) {
			semantic1(explict_return, trace);
			checkType(explict_return);
			type = createType!FCall(explict_return, argument);
		}
		semantic1(text, trace);

		if (explict_return) {
			if (!sameType(explict_return, text.type)) {
				error("Explict return doesn't match actual return", pos);
			}
		}
		//ftype.ispure = text.ispure; todo fix me
		if (!explict_return) {
			type = createType!FCall(text.type, argument);
		}
		ispure = true;
	}
}

void semantic1Impl(StringLit that, Trace* trace) {
	with (that) {
		type = createType!ArrayIndex(createType!Char);
		ispure = true;
	}
}

void semantic1Impl(ArrayLit that, Trace* trace) {
	with (that) {
		foreach (value; values) {
			semantic1(value, trace);
		}
		if (values.length == 0) {
			error("Array Literals must contain at least one element", pos);
		}
		auto current = values[0].type;
		foreach (value; values[1 .. $]) {
			if (!sameType(current, value.type)) {
				error("All elements of an array literal must be of the same type", pos);
			}
		}
		type = createType!ArrayIndex(current);
		ispure = values.map!(a => a.ispure).all;
	}
}

void semantic1Impl(ExternJS that, Trace* trace) {
	with (that) {
		type = createType!ExternType;
		ispure = true;
		if (name == "") {
			error("Improper extern", pos);
		}
	}
}

//check if a value's is equal to another type factering in implict coversions
bool sameTypeValueType(ref Expression value, Expression type) {
	assert(value.isRuntimeValue);
	assert(type.isType);
	return sameType(value.type, type) || implicitConvert(value, type);
}

bool sameTypeValueValue(ref Expression left, ref Expression right) {
	assert(left.isRuntimeValue);
	assert(right.isRuntimeValue);
	return sameType(left.type, right.type) || implicitConvertDual(left, right);
}

//checks if two types are the same
bool sameType(Expression a, Expression b) {
	assert(a.isType);
	assert(b.isType);
	alias Types = AliasSeq!(Metaclass, Char, Int, UInt, Struct, Postfix!"(*)",
			ArrayIndex, FCall, ImportType, ExternType);
	return dispatch!((a, b) => dispatch!((a, b) => sameTypeImpl(b, a), Types)(b, a), Types)(
			a.unalias, b.unalias);
}

bool sameTypeImpl(T1, T2)(T1 a, T2 b) {
	static if (!is(T1 == T2) || is(T1 == ImportType) || is(T1 == ExternType)) {
		return false;
	} else {
		alias T = T1;
		static if (is(T == Bool) || is(T == Char) || is(T == Metaclass)) {
			return true;
		} else static if (is(T == UInt) || is(T == Int)) {
			return a.size == b.size;
		} else static if (is(T == Struct)) {
			if (a.values.length != b.values.length) {
				return false;
			}
			foreach (c, t; a.values) {
				if (!sameType(t, b.values[c])) {
					return false;
				}
			}
			return true;
		} else static if (is(T == Postfix!"(*)")) {
			return sameType(a.value, b.value);
		} else static if (is(T == ArrayIndex)) {
			return sameType(a.array, b.array);
		} else static if (is(T == FCall)) {
			return sameType(a.fptr, b.fptr) && sameType(a.arg, b.arg);
		}
	}
}
//modifys value's type
//returns if converted
bool implicitConvert(ref Expression value, Expression type) {
	value = value.unalias;
	type = type.unalias;
	assert(isRuntimeValue(value));
	assert(isType(type));

	if (cast(IntLit) value && (type.isUInt || type.isInt)) {
		auto result = new Cast();
		result.implicit = true;
		result.wanted = type;
		result.type = type;
		result.value = value;
		result.process = true;
		value = result;
		return true;
	}
	if (auto ext = cast(ExternJS) value) {
		auto result = new Cast();
		result.implicit = true;
		result.wanted = type;
		result.type = type;
		result.value = value;
		result.process = true;
		value = result;
		return true;
	}
	return false;
}

//check if two values can convert implictly into each other
bool implicitConvertDual(ref Expression left, ref Expression right) {
	return implicitConvert(left, right.type) || implicitConvert(right, left.type);
}

bool castable(Expression target, Expression want) {
	target = target.unalias;
	want = want.unalias;
	if (sameType(target, want)) {
		return true;
	}
	if (sameType(target, createType!Struct())) {
		return true;
	}
	if ((cast(Int) target || cast(UInt) target) && (cast(Int) want || cast(UInt) want)) { //casting between int types
		return true;
	}
	return false;
}
