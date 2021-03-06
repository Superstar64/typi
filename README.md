
Aith is a low level functional programming language with linear types, kind based staging / macros, and levity polymorphism.
As of now aith is very early stages and very little is implemented.
See ``/documentation`` for typing rules.

# Road Map

* [x] Macro Lambda Calculus
* [x] Macro Beta Reduction
* [x] System-F
* [x] System-F ω
* [ ] New Types
* [x] Pattern Matching
* [x] Basic Linear Types
* [ ] Multiplicity Polymorphism
* [ ] Multiplicity Predicates
* [x] Levity Polymorphism
* [x] Stage Polymorphism
* [x] Modules
* [ ] Runtime Primitives
  * [ ] Booleans
  * [ ] Integers
  * [ ] Pointers
  * [ ] Arrays
  * [x] Function Pointers
  * [x] Tuples
  * [ ] Choice (Sums) 
* [x] Monadic Regions
* [ ] Hindley Milner Subset
* [x] C Code Generation
* [ ] Javascript Code Generation

# Syntax

## Modules(code)
| Description | Syntax |
|-|-|
| Module | ``module x = { code };`` |
| Inline Term | ``inline x = e; ``|
| Annotated Inline Term | ``inline _ :: σ; inline x = e; ``|
| Import | ``import x = /x'/x''/...;``|
| Function | ``function x = e;`` |
| Annotated Function | ``function _ :: σ; function x = e;``| 
| Type Synonym | ``type x = σ;`` |

## Runtime Terms(e)
| Description | Syntax |
|-|-|
| Variable | ``x`` |
| Runtime Binding | ``_let pm = e; e' ``|
| Type Abstraction | `` `\pmσ { e }`` |
| Type Abstraction | `` `pmσ => e`` |
| Type Application | ``e`(σ)`` |
| Kind Abstraction | ``` ``\pmκ => e``` |
| Kind Abstraction | ``` ``\pmκ { e }``` |
| Kind Application | ``` e``(κ) ``` |
| Extern | ``_extern "x" (σ) (τ) `` |
| Function Application | ``e e' ``|
| Function Literal | ``\pme => e`` |
| Function Literal | ``\pme { e }`` |
| Qualified Assumption | ``_when σ => e `` |
| Qualified Assumption | ``_when σ { e } `` |
| Qualified Check | ``e?`` |
| Pair Constructor (Left Associative) | ``(e,e',...)`` |
| Recursive Type Introduction | ``_pack (pmσ => σ) e `` |
| Recursive Type Introduction| ``_pack (pmσ { σ }) e `` |
| Recursive Type Elimination | ``_unpack e`` |
| Pure Region Transformer | ``_pure (π) e`` |
| Bind Region Transformer | `` _do pm = e; e' `` |
| Subtype Region Transformer | `` _cast (π) e `` |
| Read Reference | `` _read e ``
| Stack Variable Region | `` _stack (pmσ; _local pm = e) -> π { e' } `` |
| Meta Term | `` ~e `` | 

## Meta Terms(em)
| Description | Syntax |
|-|-|
| Variable | ``x`` |
| Of Course Introduction | ``!em`` |
| Binding | ``_let pm = em; em' ``|
| Macro Abstraction | ``\pm { em }``|
| Macro Abstraction | ``\pm => em ``|
| Macro Application | ``em em'``|
| Type Abstraction | `` `\pmσ { em }`` |
| Type Abstraction | `` `pmσ => em`` |
| Type Application | ``em`(σ)`` |
| Kind Abstraction | ``` ``\pmκ => em``` |
| Kind Abstraction | ``` ``\pmκ { em }``` |
| Kind Application | ``` em``(κ) ``` |
| Qualified Assumption | ``_when σ => em `` |
| Qualified Assumption | ``_when σ { em } `` |
| Qualified Check | ``em?`` |
| Runtime Term |`` #e `` | 


## Patterns(pm)
| Description | Syntax |
|-|-|
| Variable | ``(x : σ)``|
| OfCourse | ``!pm`` |

## Runtime Patterns(pme)
| Description | Syntax |
|-|-|
| Variable | ``(x : σ)``|
| Pair Destruction (Left Associative) | ``(pm, pm', ...)`` |

## Runtime Types(σ, τ, π)
| Description | Syntax |
|-|-|
| Variable | ``x`` |
| Forall | `` `\/pmσ { σ }`` |
| Forall | `` `\/pmσ => σ`` |
| KindForall | ``` ``\/s : μ => σ``` |
| KindForall | ``` ``\/s : μ { σ }``` |
| Type Operator | `` \x : κ { σ }``|
| Type Operator | `` \x : κ => σ ``|
| Type Construction | `` σ τ `` |
| Poly Operator | `` `\pmκ => σ`` |
| Poly Operator | `` `\pmκ { σ }`` |
| Poly Construction | `` σ`(κ) ``
| Function Pointer | `` τ -> σ `` |
| Function Literal Type | `` τ _function σ `` |
| Qualified Type | `` _when π => σ `` |
| Copy Predicate | ``_copy σ`` |
| Pair (Left Associative) | ``#(σ, σ', ...)`` |
| Recursive Type | `` _recursive pmσ => σ`` |
| Recursive Type | `` _recursive pmσ { σ }`` |
| Region Transformer | `` _state π σ `` |
| Region Reference | `` _reference π σ `` |
| Region Subtype | `` _outlive π π' `` |
| Meta Type | `` ~σm `` |

## Meta Types(σm, τm, πm)
| Description | Syntax |
|-|-|
| Variable | ``x`` |
| Macro | ``σm -> σm'``|
| Of Course | ``!σm``|
| Forall | `` `\/pmσ { σm }`` |
| Forall | `` `\/pmσ => σm`` |
| KindForall | ``` ``\/s : μ => σm``` |
| KindForall | ``` ``\/s : μ { σm }``` |
| Type Operator | `` \x : κ { σm }``|
| Type Operator | `` \x : κ => σm ``|
| Type Construction | `` σm τm `` |
| Poly Operator | `` `\pmκ => σm`` |
| Poly Operator | `` `\pmκ { σm }`` |
| Qualified Type | `` _when πm => σm `` |
| Runtime Type | `` #σ `` |



## Type Pattern(pmσ)
|Description | Syntax |
|-|-|
| Variable | ``x : κ`` |


## Kinds(κ,s,ρ)
| Description | Syntax |
|-|-|
| Variable | ``x`` |
| Type | `` _type s `` |
| Higher | `` κ -> κ' `` |
| Poly | `` `\/ x : μ => κ `` |
| Poly | `` `\/ x : μ { κ } `` |
| Constraint | `` _constraint `` |
| Region | `` _region `` |
| Runtime | ``_runtime ρ ρ'`` |
| Code | `` _code `` |
| Data | `` _data `` |
| Real | `` _real ρ ``|
| Imaginary (currently unused) | `` _imaginary `` |
| Meta | ``_meta`` |
| Text | ``_text`` |
| Pointer Representation | ``_pointer``|
| Struct Representation | ``_struct (ρ, ρ', ...)`` |

# Kind Pattern (pmκ)
|Description | Syntax |
|-|-|
| Variable | ``x : μ`` |

## Sorts(μ)
| Description | Syntax |
|-|-|
| Kind | ``_kind`` |
| Stage | ``_stage`` |
| Impact | ``_impact`` |
| Existance | ``_existance`` |
| Representation | ``_representation`` |

# C Compiler Requirements
* All pointers must have the same representation

# Papers
Useful / Inspirational papers:

## Implemented

### Linear Types
* [A taste of linear logic](https://homepages.inf.ed.ac.uk/wadler/papers/lineartaste/lineartaste-revised.pdf)
  * Faithfully implemented
* [The Best of Both Worlds: Linear Functional Programming without Compromise](https://jgbm.github.io/pubs/morris-icfp2016-linearity-extended.pdf) [(video)](https://youtu.be/ij9DbNTr-B8)
  * Bare bones implementation of qualified linear types.
### Levity polymorphism
* [Levity Polymorphism](https://www.microsoft.com/en-us/research/wp-content/uploads/2016/11/levity-pldi17.pdf) [(video)](https://youtu.be/lSJwXZ7vWBw)
  * Implemented with more restrictive representation lambda.
### Regions
* [Monadic Regions](https://www.cs.cornell.edu/people/fluet/research/rgn-monad/JFP06/jfp06.pdf)
  * Partially implemented, with more limited ways to create new region references 
### Compiler Design
* [Invertible Syntax Descriptions: Unifying Parsing and Pretty Printing](https://www.mathematik.uni-marburg.de/~rendel/rendel10invertible.pdf)
  * Implemented with prisms instead of partial isomorphisms.
### Algorithms
* [Demonstrating Lambda Calculus Reduction](https://www.cs.cornell.edu/courses/cs6110/2014sp/Handouts/Sestoft.pdf)
  * Applicative order reduction used for reduction.

## Related / Unused

### Linear Types
* [Linear Haskell](https://arxiv.org/pdf/1710.09756.pdf) [(video)](https://youtu.be/t0mhvd3-60Y)
* [Making Uniqueness Typing Less Unique](http://edsko.net/pubs/thesis.pdf)
* [Modelling Unique and Affine Typing using Polymorphism](http://www.edsko.net/pubs/modelling-unique-and-affine.pdf)

### Compiler Design
* [Typed Tagless Final Interpreters](http://okmij.org/ftp/tagless-final/index.html)

### General Type Systems
* [Type Systems](http://lucacardelli.name/Papers/TypeSystems.pdf)
* [System F with Type Equality Coercions](https://www.microsoft.com/en-us/research/wp-content/uploads/2007/01/tldi22-sulzmann-with-appendix.pdf)



# Copyright
Copyright © Freddy A Cubas, "Superstar64"

Licensed under GPL3 only. See LICENSE for more info.
