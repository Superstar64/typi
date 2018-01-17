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
import std.range : recurrence, drop, take;

import ast;
import error : error, Position;
import parser;

T castTo(T, Base)(Base node) {
	return cast(T) node;
}

void processModule(Module mod) {
	mod.process = true;
	auto trace = Trace(mod, null);
	foreach (symbol; mod.symbols) {
		semantic1(symbol, &trace);
		if (!symbol.ispure) {
			error("Impure expression in global", symbol.pos);
		}
	}
}

ref Expression[] values(Struct stru) {
	return stru.value.castTo!TupleLit.values;
}

bool isType(Expression expression) {
	return !!expression.type.castTo!Metaclass;
}

bool isRuntimeValue(Expression expression) {
	return !(expression.isType || expression.castTo!Import);
}

void checkRuntimeValue(Expression expression) {
	if (!isRuntimeValue(expression)) {
		error("Expected runtime value", expression.pos);
	}
}

//makes sure expression is a type or implicitly convert it to a type
void checkType(ref Expression expression) {
	if (auto tuple = expression.castTo!TupleLit) {
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
	return new T;
}

T createTypeImpl(T)(int size) if (is(T == Int) || is(T == UInt)) {
	auto type = new T;
	type.size = size;
	return type;
}

T createTypeImpl(T)(Expression value) if (is(T == Postfix!"(*)")) {
	auto type = new T;
	type.value = value;
	return type;
}

T createTypeImpl(T)(Expression[] values = null) if (is(T == Struct)) {
	auto type = new T;
	auto tuple = new TupleLit();
	tuple.values = values;
	semantic1Head(tuple);
	type.value = tuple;
	return type;
}

T createTypeImpl(T)(Expression fptr, Expression arg) if (is(T == FuncCall)) {
	auto type = new T;
	type.fptr = fptr;
	type.arg = arg;
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
	that.process = true;
}

void semantic1(ref Statement that, Trace* trace) {
	dispatch!(semantic1, VarDef, Expression, Assign)(that, trace);
}

void semantic1(VarDef that, Trace* trace) {
	semantic1(that.definition, trace);
	that.ispure = that.definition.ispure;
	if (!that.manifest) {
		that.ispure = false;
		checkRuntimeValue(that.definition);
	}
	if (that.explicitType) {
		semantic1(that.explicitType, trace);
		checkType(that.explicitType);
		if (!sameTypeValueType(that.definition, that.explicitType)) {
			error("types don't match", that.pos);
		}
	}
	if (auto scopeVar = that.castTo!ScopeVarDef) {
		if (!that.manifest) {
			scopeVar.func = trace.range.map!(a => a.node)
				.map!(a => a.castTo!FuncLit).filter!(a => !!a).front;
		}
	}
	if (auto moduleVar = that.castTo!ModuleVarDef) {
		if (!that.manifest) {
			auto mod = trace.range.reduce!"b".node.castTo!Module;
			mod.exports[that.name] = Symbol(moduleVar);
		}
	}
}

void semantic1(Assign that, Trace* trace) {
	semantic1(that.left, trace);
	semantic1(that.right, trace);
	if (!(sameType(that.left.type, that.right.type) || implicitConvert(that.right, that.left.type))) {
		error("= only works on the same type", that.pos);
	}
	if (!that.left.lvalue) {
		error("= only works on lvalues", that.pos);
	}
	that.ispure = that.left.ispure && that.right.ispure;
}

void semantic1(ref Expression that, Trace* trace) {
	if (that.process) {
		//todo check for cycles
		return;
	}
	that.process = true;
	auto nextTrace = Trace(that, trace);
	trace = &nextTrace;
	dispatch!(semantic1ExpressionImpl, Metaclass, Bool, Char, Int, UInt, Postfix!"(*)",
			Import, IntLit, CharLit, BoolLit, Struct, TupleLit, FuncArgument, If, While,
			New, NewArray, Cast, ArrayIndex, FuncCall, Slice, Scope, FuncLit,
			StringLit, ArrayLit, ExternJS, Binary!"*", Binary!"/",
			Binary!"%", Binary!"+", Binary!"-", Binary!"~", Binary!"==",
			Binary!"!=", Binary!"<=", Binary!">=", Binary!"<", Binary!">",
			Binary!"&&", Binary!"||", Prefix!"+", Prefix!"-", Prefix!"*",
			Prefix!"/", Prefix!"&", Prefix!"!", Expression)(that, trace);
	assert(that.type);
	assert(that.type.isType);
	assert(!cast(Variable) that);
}
//for types that cases that requre ast modification
void semantic1ExpressionImpl(ref Expression that, Trace* trace) {
	dispatch!(semantic1ExpressionImplWritable, Variable, Dot)(that, trace, that);
}
//bug variable still in ast after this pass
void semantic1ExpressionImplWritable(Variable that, Trace* trace, ref Expression output) {
	Trace subTrace;
	auto source = trace.search(that.name, subTrace);
	if (source is null) {
		error("Unknown variable", that.pos);
	}

	if (source.definition.type is null) {
		semantic1(source.definition, &subTrace);
	}
	Expression thealias;
	if (source.manifest) {
		thealias = source.definition;
	} else {
		if (auto scopeDef = source.castTo!ScopeVarDef) {
			auto scopeRef = new ScopeVarRef();
			scopeRef.definition = scopeDef;
			scopeRef.ispure = true;
			scopeRef.type = source.type;
			scopeRef.lvalue = true;
			thealias = scopeRef;
		} else if (auto moduleDef = source.castTo!ModuleVarDef) {
			auto moduleRef = new ModuleVarRef();
			moduleRef.definition = moduleDef;
			moduleRef.ispure = false;
			moduleRef.type = source.type;
			moduleRef.lvalue = true;
			thealias = moduleRef;
		} else {
			assert(0);
		}
	}
	assert(thealias.type);
	if (auto scopeVarRef = thealias.castTo!ScopeVarRef) {
		checkNotClosure(scopeVarRef, trace, that.pos);
	}
	output = thealias;
}

void checkNotClosure(ScopeVarRef that, Trace* trace, Position pos) {
	auto funcRange = trace.range.map!(a => a.node).map!(a => a.castTo!FuncLit).filter!(a => !!a);
	if (funcRange.front !is that.definition.func) {
		error("Closures not supported", pos);
	}
}

void semantic1ExpressionImplWritable(Dot that, Trace* trace, ref Expression output) {
	semantic1(that.value, trace);
	semantic1Dot(that.value.type, trace, that, output);
	that.ispure = that.value.ispure;
}

void semantic1Dot(Expression that, Trace* trace, Dot dot, ref Expression output) {
	auto nextTrace = Trace(that, trace);
	trace = &nextTrace;
	dispatch!(semantic1DotImpl, ArrayIndex, ImportType, Expression)(that, trace, dot, output);
}

void semantic1DotImpl(ArrayIndex that, Trace* trace, Dot dot, ref Expression output) {
	if (dot.index != "length") {
		semantic1DotImpl(that.castTo!Expression, trace, dot, output);
		return;
	}
	dot.type = createType!UInt(0);
}

void semantic1DotImpl(ImportType that, Trace* trace, Dot dot, ref Expression output) {
	auto imp = dot.value.castTo!Import;
	if (dot.index !in imp.mod.symbols) {
		error(dot.index ~ " doesn't exist in module", dot.pos);
	}
	auto definition = imp.mod.symbols[dot.index];
	if (!definition.visible) {
		error(dot.index ~ " is not visible", dot.pos);
	}
	ModuleVarRef thealias = new ModuleVarRef();
	thealias.definition = definition;
	thealias.ispure = false;
	thealias.type = definition.type;
	thealias.lvalue = true;
	if (definition.type is null) {
		auto definitionTrace = Trace(imp.mod, null);
		semantic1(thealias.definition, &definitionTrace);
	}
	output = thealias;
}

void semantic1DotImpl(Expression that, Trace* trace, Dot dot, ref Expression output) {
	error("Unable to dot", that.pos);
}

Metaclass metaclass;
static this() {
	metaclass = new Metaclass();
	metaclass.type = metaclass;
	metaclass.ispure = true;
}

void semantic1ExpressionImpl(Metaclass that, Trace* trace) {
}

void semantic1ExpressionImpl(Import that, Trace* trace) {
	that.type = createType!ImportType;
	that.ispure = true;
}

void semantic1HeadImpl(T)(T that)
		if (is(T == Bool) || is(T == Char) || is(T == ImportType) || is(T == ExternType)) {
	that.type = metaclass;
	that.ispure = true;
}

void semantic1HeadImpl(T)(T that) if (is(T == Int) || is(T == UInt)) {
	that.type = metaclass;
	that.ispure = true;
	if (that.size == 0) {
		return;
	}
	if (!recurrence!((a, n) => a[n - 1] / 2)(that.size).until(1).map!(a => a % 2 == 0).all) {
		error("Bad Int Size", that.pos);
	}

}

void semantic1ExpressionImpl(T)(T that, Trace* trace)
		if (is(T == Bool) || is(T == Char) || is(T == Int) || is(T == UInt)) {
	semantic1Head(that);
}

void semantic1HeadImpl(T)(T that) if (is(T == Postfix!"(*)")) {
	checkType(that.value);
	that.type = metaclass;
	that.ispure = true;
}

void semantic1ExpressionImpl(T)(T that, Trace* trace) if (is(T == Postfix!"(*)")) {
	semantic1(that.value, trace);
	semantic1Head(that);
}

void semantic1ExpressionImpl(IntLit that, Trace* trace) {
	if (that.usigned) {
		that.type = createType!UInt(0);
	} else {
		that.type = createType!Int(0);
	}
	that.ispure = true;
}

void semantic1ExpressionImpl(CharLit that, Trace* trace) {
	that.type = createType!Char;
	that.ispure = true;
}

void semantic1ExpressionImpl(BoolLit that, Trace* trace) {
	that.type = createType!Bool;
	that.ispure = true;
}

void semantic1HeadImpl(T)(T that) if (is(T == Struct)) {
	if (!that.value.castTo!TupleLit) {
		error("expected tuple lit after struct", that.pos);
	}
	that.values.each!checkType;
	that.type = metaclass;
	that.ispure = true;
}

void semantic1ExpressionImpl(Struct that, Trace* trace) {
	semantic1(that.value, trace);
	semantic1Head(that);
}

void semantic1Head(TupleLit that) {
	if (that.values.map!(a => !!a.castTo!Metaclass).all) {
		auto cycle = new Struct();
		cycle.value = that;
		semantic1Head(cycle);
		that.type = cycle;
	} else {
		that.type = createType!Struct(that.values.map!(a => a.type).array);
	}
	that.ispure = that.values.map!(a => a.ispure).all;
}

void semantic1ExpressionImpl(TupleLit that, Trace* trace) {
	foreach (value; that.values) {
		semantic1(value, trace);
	}

	semantic1Head(that);
}

void semantic1ExpressionImpl(FuncArgument that, Trace* trace) {
	foreach (node; trace.range.map!(a => a.node)) {
		if (auto func = node.castTo!FuncLit) {
			that.func = func;
			that.type = func.argument;
			//todo make lvalue-able
			return;
		}
	}
	error("$@ without function", that.pos);
}

void semantic1ExpressionImpl(If that, Trace* trace) {
	semantic1(that.cond, trace);
	semantic1(that.yes, trace);
	semantic1(that.no, trace);
	if (!that.cond.type.castTo!Bool) {
		error("Boolean expected in if expression", that.cond.pos);
	}
	if (!sameTypeValueValue(that.yes, that.no)) {
		error("If expression with the true and false parts having different types", that.pos);
	}
	that.type = that.yes.type;
	that.ispure = that.cond.ispure && that.yes.ispure && that.no.ispure;
}

void semantic1ExpressionImpl(While that, Trace* trace) {
	semantic1(that.cond, trace);
	semantic1(that.state, trace);
	if (!that.cond.type.castTo!Bool) {
		error("Boolean expected in while expression", that.cond.pos);
	}
	that.type = createType!Struct();
	that.ispure = that.cond.ispure && that.state.ispure;
}

void semantic1ExpressionImpl(New that, Trace* trace) {
	semantic1(that.value, trace);
	that.type = createType!(Postfix!"(*)")(that.value.type);
	that.ispure = that.value.ispure;
}

void semantic1ExpressionImpl(NewArray that, Trace* trace) {
	semantic1(that.length, trace);
	semantic1(that.value, trace);
	if (!sameTypeValueType(that.length, createType!UInt(0))) {
		error("Can only create an array with length of UInts", that.length.pos);
	}
	that.type = createType!ArrayIndex(that.value.type);
	that.ispure = that.length.ispure && that.value.ispure;
}

void semantic1ExpressionImpl(Cast that, Trace* trace) {
	semantic1(that.value, trace);
	semantic1(that.wanted, trace);
	checkType(that.wanted);
	if (!castable(that.value.type, that.wanted)) {
		error("Unable to cast", that.pos);
	}
	that.type = that.wanted;
	that.ispure = that.value.ispure;
}

bool castable(Expression target, Expression want) {
	target = target;
	want = want;
	if (sameType(target, want)) {
		return true;
	}
	if (sameType(target, createType!Struct())) {
		return true;
	}
	if ((target.castTo!Int || target.castTo!UInt) && (want.castTo!Int || want.castTo!UInt)) { //casting between int types
		return true;
	}
	return false;
}

void semantic1HeadImpl(T)(T that) if (is(T == ArrayIndex)) {
	checkType(that.index);
	if (!sameType(that.index, createType!Struct())) {
		error("Expected empty type in array type", that.pos);
	}
	that.type = metaclass;
	that.ispure = true;
}

void semantic1ExpressionImpl(ArrayIndex that, Trace* trace) {
	semantic1(that.array, trace);
	semantic1(that.index, trace);
	if (that.array.isType) {
		semantic1Head(that);
	} else {
		dispatch!(semantic1ArrayImpl, ArrayIndex, Struct, Expression)(that.array.type, that, trace);
	}
}

void semantic1ArrayImpl(ArrayIndex type, ArrayIndex that, Trace* trace) {
	if (!sameTypeValueType(that.index, createType!UInt(0))) {
		error("Can only index an array with UInts", that.pos);
	}
	that.type = type.array;
	that.lvalue = true;
	that.ispure = that.array.ispure && that.index.ispure;
}

void semantic1ArrayImpl(Struct type, ArrayIndex that, Trace* trace) {
	auto indexLit = that.index.castTo!IntLit;
	if (!indexLit) {
		error("Expected integer when indexing struct", that.index.pos);
	}
	uint index = indexLit.value.to!uint;
	if (index >= type.values.length) {
		error("Index number to high", that.pos);
	}
	that.type = type.values[index];
	that.lvalue = that.array.lvalue;
}

void semantic1ArrayImpl(Expression type, ArrayIndex that, Trace* trace) {
	error("Unable able to index", that.pos);
}

void semantic1HeadImpl(T)(T that) if (is(T == FuncCall)) {
	checkType(that.fptr);
	checkType(that.arg);
	that.type = metaclass;
	that.ispure = true;
}

void semantic1ExpressionImpl(FuncCall that, Trace* trace) {
	semantic1(that.fptr, trace);
	semantic1(that.arg, trace);
	if (that.fptr.isType || that.arg.isType) {
		semantic1Head(that);
	} else {
		auto fun = that.fptr.type.castTo!FuncCall;
		if (!fun) {
			error("Not a function", that.pos);
		}
		if (!sameTypeValueType(that.arg, fun.arg)) {
			error("Unable to call function with the  argument's type", that.pos);
		}
		that.type = fun.fptr;
		that.ispure = that.fptr.ispure && that.arg.ispure /* todo fix me && fun.ispure*/ ;
	}
}

void semantic1ExpressionImpl(Slice that, Trace* trace) {
	semantic1(that.array, trace);
	semantic1(that.left, trace);
	semantic1(that.right, trace);
	if (!that.array.type.castTo!ArrayIndex) {
		error("Not an array", that.pos);
	}
	if (!(sameTypeValueType(that.right, createType!UInt(0))
			&& sameTypeValueType(that.left, createType!UInt(0)))) {
		error("Can only index an array with UInts", that.pos);
	}
	that.type = that.array.type;
	that.ispure = that.array.ispure && that.left.ispure && that.right.ispure;
}

void semantic1ExpressionImpl(string op)(Binary!op that, Trace* trace) {
	semantic1(that.left, trace);
	semantic1(that.right, trace);
	static if (["*", "/", "%", "+", "-", "<=", ">=", ">", "<"].canFind(op)) {
		auto ty = that.left.type;
		if (!((ty.castTo!UInt || ty.castTo!Int) && (sameTypeValueValue(that.left, that.right)))) {
			error(op ~ " only works on Ints or UInts of the same Type", that.pos);
		}
		static if (["<=", ">=", ">", "<"].canFind(op)) {
			that.type = createType!Bool;
		} else {
			that.type = ty;
		}
		that.ispure = that.left.ispure && that.right.ispure;
	} else static if (op == "~") {
		auto ty = that.left.type;
		if (!ty.castTo!ArrayIndex && sameType(ty, that.right.type)) {
			error("~ only works on Arrays of the same Type", that.pos);
		}
		that.type = ty;
		that.ispure = that.left.ispure && that.right.ispure;
	} else static if (["==", "!="].canFind(op)) {
		if (!(sameTypeValueValue(that.left, that.right))) {
			error(op ~ " only works on the same Type", that.pos);
		}
		that.type = createType!Bool;
		that.ispure = that.left.ispure && that.right.ispure;
	} else static if (["&&", "||"].canFind(op)) {
		auto ty = that.left.type;
		if (!(ty.castTo!Bool && sameType(ty, that.right.type))) {
			error(op ~ " only works on Bools", that.pos);
		}
		that.type = createType!Bool;
		that.ispure = that.left.ispure && that.right.ispure;
	} else {
		static assert(0);
	}
}

void semantic1ExpressionImpl(string op)(Prefix!op that, Trace* trace) {
	semantic1(that.value, trace);
	static if (op == "-") {
		if (!that.value.type.castTo!Int) {
			error("= only works Signed Ints", that.pos);
		}
		that.type = that.value.type;
		that.ispure = that.value.ispure;
	} else static if (op == "*") {
		if (!that.value.type.castTo!(Postfix!"(*)")) {
			error("* only works on pointers", that.pos);
		}
		that.type = that.value.type.castTo!(Postfix!"(*)").value;
		that.lvalue = true;
		that.ispure = that.value.ispure;
	} else static if (op == "&") {
		if (!that.value.lvalue) {
			error("& only works lvalues", that.pos);
		}

		static void assignHeapImpl(T)(T that, Trace* trace) {
			auto nextTrace = Trace(that, trace);
			trace = &nextTrace;
			static if (is(T == ScopeVarRef) || is(T == ModuleVarRef)) {
				that.definition.heap = true;
			} else static if (is(T == Dot)) {
				assignHeap(that.value, trace);
			}
		}

		static void assignHeap(Expression that, Trace* trace) {
			return dispatch!(assignHeapImpl, ScopeVarRef, ModuleVarRef, Dot, Expression)(that,
					trace);
		}

		assignHeap(that.value, trace);

		that.type = createType!(Postfix!"(*)")(that.value.type);
		that.ispure = that.value.ispure;
	} else static if (op == "!") {
		if (!that.value.type.castTo!Bool) {
			error("! only works on Bools", that.pos);
		}
		that.type = that.value.type;
		that.ispure = that.value.ispure;
	} else static if (["+", "/"].canFind(op)) {
		error(op ~ " not supported", that.pos);
	} else {
		static assert(0);
	}
}

void semantic1ExpressionImpl(Scope that, Trace* trace) {
	that.ispure = true;
	foreach (symbol; that.symbols) {
		semantic1(symbol, trace);
	}
	foreach (state; that.states) {
		semantic1(state, trace);
		trace.context.pass(state);
		that.ispure = that.ispure && state.ispure;
	}
	if (that.last is null) {
		that.last = new TupleLit();
	}
	semantic1(that.last, trace);
	that.type = that.last.type;
}

void semantic1ExpressionImpl(FuncLit that, Trace* trace) {
	semantic1(that.argument, trace);
	checkType(that.argument);

	if (that.explict_return) {
		semantic1(that.explict_return, trace);
		checkType(that.explict_return);
		that.type = createType!FuncCall(that.explict_return, that.argument);
	}
	semantic1(that.text, trace);

	if (that.explict_return) {
		if (!sameType(that.explict_return, that.text.type)) {
			error("Explict return doesn't match actual return", that.pos);
		}
	}
	//ftype.ispure = text.ispure; todo fix me
	if (!that.explict_return) {
		that.type = createType!FuncCall(that.text.type, that.argument);
	}
	that.ispure = true;
	auto mod = trace.range.reduce!"b".node.castTo!Module;
	mod.exports[that.name] = Symbol(that);
}

void semantic1ExpressionImpl(StringLit that, Trace* trace) {
	that.type = createType!ArrayIndex(createType!Char);
	that.ispure = true;
}

void semantic1ExpressionImpl(ArrayLit that, Trace* trace) {
	foreach (value; that.values) {
		semantic1(value, trace);
	}
	if (that.values.length == 0) {
		error("Array Literals must contain at least one element", that.pos);
	}
	auto current = that.values[0].type;
	foreach (value; that.values[1 .. $]) {
		if (!sameType(current, value.type)) {
			error("All elements of an array literal must be of the same type", that.pos);
		}
	}
	that.type = createType!ArrayIndex(current);
	that.ispure = that.values.map!(a => a.ispure).all;
}

void semantic1ExpressionImpl(ExternJS that, Trace* trace) {
	that.type = createType!ExternType;
	that.ispure = true;
	if (that.name == "") {
		error("Improper extern", that.pos);
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
			ArrayIndex, FuncCall, ImportType, ExternType);
	return dispatch!((a, b) => dispatch!((a, b) => sameTypeImpl(b, a), Types)(b, a), Types)(a, b);
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
		} else static if (is(T == FuncCall)) {
			return sameType(a.fptr, b.fptr) && sameType(a.arg, b.arg);
		}
	}
}
//modifys value's type
//returns if converted
bool implicitConvert(ref Expression value, Expression type) {
	value = value;
	type = type;
	assert(isRuntimeValue(value));
	assert(isType(type));

	if (value.castTo!IntLit && (type.castTo!UInt || type.castTo!Int)) {
		auto result = new Cast();
		result.implicit = true;
		result.wanted = type;
		result.type = type;
		result.value = value;
		result.process = true;
		value = result;
		return true;
	}
	if (auto ext = value.castTo!ExternJS) {
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
