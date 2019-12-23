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
module semantic.ast;

import std.bigint;
import std.meta;
import std.typecons;
import std.traits;

import misc;
import jsast;
import genericast;

static import Codegen = codegen.ast;
static import Parser = parser.ast;
import misc;

public import semantic.astimpl : specialize, toRuntime;

//be catious about https://issues.dlang.org/show_bug.cgi?id=20312

interface CompileTimeExpression {
	CompileTimeType type();

	Expression castToExpression();
	Symbol castToSymbol();
	Type castToType();
	Import castToImport();

	T castTo(T : Expression)() {
		return castToExpression;
	}

	T castTo(T : Symbol)() {
		return castToSymbol;
	}

	T castTo(T : Type)() {
		return castToType;
	}

	T castTo(T : Import)() {
		return castToImport;
	}
}

T castTo(T)(CompileTimeExpression expression) {
	return expression.castTo!T;
}

interface Expression : CompileTimeExpression {
	Type type();
	Tuple!()[PolymorphicVariable] generics();
	Expression specialize(Type[PolymorphicVariable] moves);
	Codegen.Expression toRuntime();
}

interface Symbol : Expression {
	bool strong();
	Codegen.Symbol toRuntime();
}

struct ModuleAlias {
	CompileTimeExpression element;
	bool visible;
}

class Module {
	ModuleAlias[string] aliases;
	Symbol[string] exports;
	Parser.ModuleVarDef[string] rawSymbols;
	Parser.ModuleVarDef[] rawSymbolsOrdered;

	Codegen.Module toRuntime() {
		import codegen.astimpl : make;

		Codegen.Symbol[string] result;
		foreach (key; exports.byKey) {
			auto value = exports[key];
			if (value.generics.length == 0) {
				result[key] = value.toRuntime();
			}
		}
		return make!(Codegen.Module)(result);
	}
}

interface _ModuleVar : Symbol {
	Codegen.ModuleVar toRuntime();
}

interface ModuleVar : _ModuleVar {
	Type type();
	Tuple!()[PolymorphicVariable] generics();
	Expression value();
	string name();
	bool strong();
	SymbolId id();
}

interface Pattern : CompileTimeExpression {
	Type type();
	Pattern specialize(Type[PolymorphicVariable] moves);
	Codegen.Pattern toRuntime();
}

interface NamedPattern : Pattern {
	Type type();
	FunctionArgument argument();
}

interface TuplePattern : Pattern {
	Type type();
	Pattern[] matches();
}

interface FunctionLiteral : Symbol {
	Type type();
	Tuple!()[PolymorphicVariable] generics();
	string name();
	bool strong();
	SymbolId id();
	Pattern argument();
	Lazy!(Expression) text();
}

interface Var : Expression {
	string name();

	Codegen.Var toRuntime();
}

interface _FunctionArgument : Var {
	FunctionArgument specialize(Type[PolymorphicVariable] moves);
	Codegen.FunctionArgument toRuntime();
}

interface FunctionArgument : _FunctionArgument {
	Type type();
	Tuple!()[PolymorphicVariable] generics();
	string name();
	VarId id();
}

interface _ScopeVar : Var {
	ScopeVar specialize(Type[PolymorphicVariable] moves);
	override Codegen.ScopeVar toRuntime();
}

interface ScopeVar : _ScopeVar {
	Type type();
	Tuple!()[PolymorphicVariable] generics();
	string name();
	VarId id();
}

interface ScopeVarDef : Expression {
	Type type();
	Tuple!()[PolymorphicVariable] generics();
	ScopeVar variable();
	Expression value();
	Expression last();
}

interface CastPartial : CompileTimeExpression {
	CompileTimeType type();
	Type value();
}

interface Import : CompileTimeExpression {
	CompileTimeType type();
	Module mod();
}

interface IntLit : Expression {
	Type type();
	Tuple!()[PolymorphicVariable] generics();
	BigInt value();
}

interface CharLit : Expression {
	Type type();
	Tuple!()[PolymorphicVariable] generics();
	dchar value();
}

interface BoolLit : Expression {
	Type type();
	Tuple!()[PolymorphicVariable] generics();
	bool yes();
}

interface TupleLit : Expression {
	Type type();
	Tuple!()[PolymorphicVariable] generics();
	Expression[] values();
}

interface If : Expression {
	Type type();
	Tuple!()[PolymorphicVariable] generics();
	Expression cond();
	Expression yes();
	Expression no();
}

interface While : Expression {
	Type type();
	Tuple!()[PolymorphicVariable] generics();
	Expression cond();
	Expression state();
}

interface New : Expression {
	Type type();
	Tuple!()[PolymorphicVariable] generics();
	Expression value();
}

interface NewArray : Expression {
	Type type();
	Tuple!()[PolymorphicVariable] generics();
	Expression length();
	Expression value();
}

interface CastInteger : Expression {
	Type type();
	Tuple!()[PolymorphicVariable] generics();
	Expression value();
}

interface Length : Expression {
	Type type();
	Tuple!()[PolymorphicVariable] generics();
	Expression value();
}

interface Index : Expression {
	Type type();
	Tuple!()[PolymorphicVariable] generics();
	Expression array();
	Expression index();
}

interface IndexAddress : Expression {
	Type type();
	Tuple!()[PolymorphicVariable] generics();
	Expression array();
	Expression index();
}

interface TupleIndex : Expression {
	Type type();
	Tuple!()[PolymorphicVariable] generics();
	Expression tuple();
	uint index();
}

interface TupleIndexAddress : Expression {
	Type type();
	Tuple!()[PolymorphicVariable] generics();
	Expression tuple();
	uint index();
}

interface Call : Expression {
	Type type();
	Tuple!()[PolymorphicVariable] generics();
	Expression calle();
	Expression argument();
}

interface Slice : Expression {
	Type type();
	Tuple!()[PolymorphicVariable] generics();
	Expression array();
	Expression left();
	Expression right();
}

interface Binary(string op) : Expression {
	Type type();
	Tuple!()[PolymorphicVariable] generics();
	Expression left();
	Expression right();
}

interface Prefix(string op) : Expression {
	Type type();
	Tuple!()[PolymorphicVariable] generics();
	Expression value();
}

interface Deref : Expression {
	Type type();
	Tuple!()[PolymorphicVariable] generics();
	Expression value();
}

interface Scope : Expression {
	Type type();
	Tuple!()[PolymorphicVariable] generics();
	Expression pass();
	Expression last();
}

interface Assign : Expression {
	Type type();
	Tuple!()[PolymorphicVariable] generics();
	Expression left();
	Expression right();
	Expression last();
}

interface StringLit : Expression {
	Type type();
	Tuple!()[PolymorphicVariable] generics();
	string value();
}

interface ArrayLit : Expression {
	Type type();
	Tuple!()[PolymorphicVariable] generics();
	Expression[] values();
}

interface ExternJs : Expression {
	Type type();
	Tuple!()[PolymorphicVariable] generics();
	string name();
}

interface CompileTimeType : CompileTimeExpression {
	string toString();
}

interface Type : CompileTimeType {
	Tuple!()[PolymorphicVariable] generics();
	Type specialize(Type[PolymorphicVariable] moves);
	Codegen.Type toRuntime();
}

interface PolymorphicVariable : Type {
}

interface NormalPolymorphicVariable : PolymorphicVariable {
}

interface NumberPolymorphicVariable : PolymorphicVariable {
}

interface TuplePolymorphicVariableImpl : PolymorphicVariable {
}

interface TuplePolymorphicVariable : Type {
	PolymorphicVariable id();
	Type[] values();
}

interface TypeBool : Type {
}

interface TypeChar : Type {
}

interface TypeInt : Type {
	uint size();
	bool signed();
}

interface TypeStruct : Type {
	Type[] values();
}

interface TypeArray : Type {
	Type array();
}

interface TypeFunction : Type {
	Type result();
	Type argument();
}

interface TypePointer : Type {
	Type value();
}

//dark corners
class TypeMetaclass : CompileTimeType {
	CompileTimeType _type;
	override CompileTimeType type() {
		return _type;
	}

	this() {
	}

	import semantic.astimpl;

	mixin DefaultCast;

	override string toString() {
		return "metaclass";
	}
}

interface TypeImport : CompileTimeType {
}

alias RuntimeType(T : ModuleVar) = Codegen.ModuleVar;
alias RuntimeType(T : Pattern) = Codegen.Pattern;
alias RuntimeType(T : NamedPattern) = Codegen.NamedPattern;
alias RuntimeType(T : TuplePattern) = Codegen.TuplePattern;
alias RuntimeType(T : FunctionLiteral) = Codegen.FunctionLiteral;
alias RuntimeType(T : FunctionArgument) = Codegen.FunctionArgument;
alias RuntimeType(T : ScopeVar) = Codegen.ScopeVar;
alias RuntimeType(T : ScopeVarDef) = Codegen.ScopeVarDef;
alias RuntimeType(T : IntLit) = Codegen.IntLit;
alias RuntimeType(T : CharLit) = Codegen.CharLit;
alias RuntimeType(T : BoolLit) = Codegen.BoolLit;
alias RuntimeType(T : TupleLit) = Codegen.TupleLit;
alias RuntimeType(T : If) = Codegen.If;
alias RuntimeType(T : While) = Codegen.While;
alias RuntimeType(T : New) = Codegen.New;
alias RuntimeType(T : NewArray) = Codegen.NewArray;
alias RuntimeType(T : CastInteger) = Codegen.CastInteger;
alias RuntimeType(T : Length) = Codegen.Length;
alias RuntimeType(T : Index) = Codegen.Index;
alias RuntimeType(T : IndexAddress) = Codegen.IndexAddress;
alias RuntimeType(T : TupleIndex) = Codegen.TupleIndex;
alias RuntimeType(T : TupleIndexAddress) = Codegen.TupleIndexAddress;
alias RuntimeType(T : Call) = Codegen.Call;
alias RuntimeType(T : Slice) = Codegen.Slice;
alias RuntimeType(T : Binary!op, string op) = Codegen.Binary!op;
alias RuntimeType(T : Prefix!op, string op) = Codegen.Prefix!op;
alias RuntimeType(T : Deref) = Codegen.Deref;
alias RuntimeType(T : Scope) = Codegen.Scope;
alias RuntimeType(T : Assign) = Codegen.Assign;
alias RuntimeType(T : StringLit) = Codegen.StringLit;
alias RuntimeType(T : ArrayLit) = Codegen.ArrayLit;
alias RuntimeType(T : ExternJs) = Codegen.ExternJs;
alias RuntimeType(T : TypeChar) = Codegen.TypeChar;
alias RuntimeType(T : TypeBool) = Codegen.TypeBool;
alias RuntimeType(T : TypeInt) = Codegen.TypeInt;
alias RuntimeType(T : TypeStruct) = Codegen.TypeStruct;
alias RuntimeType(T : TypeArray) = Codegen.TypeArray;
alias RuntimeType(T : TypePointer) = Codegen.TypePointer;
alias RuntimeType(T : TypeFunction) = Codegen.TypeFunction;
