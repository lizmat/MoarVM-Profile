[![Actions Status](https://github.com/lizmat/MoarVM-Profile/actions/workflows/linux.yml/badge.svg)](https://github.com/lizmat/MoarVM-Profile/actions) [![Actions Status](https://github.com/lizmat/MoarVM-Profile/actions/workflows/macos.yml/badge.svg)](https://github.com/lizmat/MoarVM-Profile/actions) [![Actions Status](https://github.com/lizmat/MoarVM-Profile/actions/workflows/windows.yml/badge.svg)](https://github.com/lizmat/MoarVM-Profile/actions)

NAME
====

MoarVM::Profile - Raku interface to MoarVM profiles

SYNOPSIS
========

```raku
use MoarVM::Profile;
my $profile = MoarVM::Profile("foo.sql");  # generated SQL
.say for $profile.routines.grep(*.is-user);
# 2: <unit-outer> (-e:1)
# 107: <unit> (-e:1)
# 112: (block) (-e:1)
# 113: foo (-e:1)
```

DESCRIPTION
===========

The `MoarVM::Profile` distribution provides a Raku interface for the information provided by the MoarVM/Rakudo code profiling information. It is intended to be used in generally applicable applications, but also for ad-hoc profiling situations and benchmarking.

MoarVM::Profile
===============

The main class provided by this distribution is the `MoarVM::Profile` class. Instantiation happens with the `.new` method, which may take:

### string with code to be executed

Creates the `MoarVM::Profile` object with the profile information resulting from executing the given code, without creating a permanent SQLite database file.

### path to script to execute

Creates the `MoarVM::Profile` object with the profile information resulting from executing the code in the given `Path::IO`. If the named argument `:create` is specified with a true value, a permanent SQLite database file will be created with the ".db" extension.

If there is already a SQLite database with the ".db" extension, then that will be used, unless the `:rerun` named argument is specified with a true value.

### path to pre-generated file with SQL statements (extension: .sql)

Creates the `MoarVM::Profile` object from the pre-generated SQL in the given `Path::IO`. If the named argument `:create` is specified with a true value, a permanent SQLite database file will be created with the ".db" extension.

### path to pre-generated database file (extension: .db)

Creates the `MoarVM::Profile` object from the given SQLite database.

Methods
-------

### calls

Returns a `List` of `MoarVM::Profile::Call` objects, where the index of the object is the same as the `.id` of the object.

```raku
my $call := $profile.calls[$call-id];
```

calls-overview
--------------

Returns the `MoarVM::Profile::CallsOverview` object associated with this profile.

### db

The `DB::SQLite` database handle connected to the database associated with the profile.

### deallocations

Returns a `List` of `MoarVM::Profile::Deallocation` objects, one for each deallocation having been done.

```raku
.say for $profile.deallocations;
```

### gc-overview

Returns a `MoarVM::Profile::GCOverview` object. Please note that this will only contain sensible information if at least one garbage collection has been done.

```raku
say $profile.gc-overview;
```

### gcs

Returns a `List` of `MoarVM::Profile::GC` objects, one for each garbage collection run having been done.

```raku
.say for $profile.gcs;
```

### query

Perform a SQL query on the database associated with the profile.

### routines

Returns a `List` of `MoarVM::Profile::Routine` objects, where the index of the object is the same as the `.id` of the object.

```raku
my $routine := $profile.routine[$routine-id];
```

### types

Returns a `List` of `MoarVM::Profile::Type` objects, where the index of the object is the same as the `.id` of the object.

```raku
my $type := $profile.types[$type-id];
```

SUBTYPES
========

This distribution provides a number of `MoarVM::Profile::xxx` subtypes who share a number of methods.

Methods
-------

### columns

String with all columns concatenated of associated table, or `Nil` if the class works on a compound SQL statement.

### select

String with a SQL statement to select all columns of the associated table(s).

### table

String with the name of the associated table, or `Nil` if the class works on a compound SQL statement.

MoarVM::Profile::Allocation
===========================

An object containing allocation information about a given `MoarVM::Profile::Call` and a given `MoarVM::Profile::Type`.

Methods
-------

  * call-id - ID of the associated M:P:Call object

  * count

  * jit

  * replaced

  * spesh

  * type-id - ID of the associated M:P:Type object

MoarVM::Profile::Call
=====================

An object containing information about a given call to a `MoarVM::Profile::Routine`.

Methods
-------

  * deopt-all

  * deopt-one

  * exclusive-time

  * entries

  * first-entry-time

  * highest-child-id

  * id

  * inclusive-time

  * inlined-entries

  * jit-entries

  * osr

  * rec-depth

  * routine-id

  * spesh-entries

### allocations

Returns a `List` with `MoarVM::Profile::Allocation` objects for this routine.

### ancestry

Returns a `List` with `MoarVM::Profile::Call` objects of the parents of this call.

### parent

Returns the `MoarVM::Profile::Call` object of the parent of this call, or `Nil` if no parent could be found.

### parent-id

Returns the `id` of the parent of this call.

MoarVM::Profile::CallsOverview
==============================

An object containing summary information about all calls in this profile.

Methods
-------

  * deopt-all-total

  * deopt-one-total

  * entries-total

  * inlined-entries-total

  * jit-entries-total

  * osr-total

  * spesh-entries-total

MoarVM::Profile::Deallocation
=============================

An object containing information about a de-allocation of a given garbage collect sequence number, the thread performing the garbage collection, and the type being garbage collected.

Methods
-------

  * gc-seq-num

  * gc-thread-id

  * gen2

  * nursery-fresh

  * nursery-seen

  * type-id

MoarVM::Profile::GC
===================

An object containing information about a garbage collection run.

Methods
-------

  * cleared-bytes

  * full

  * gen2-roots

  * promoted-bytes

  * responsible

  * retained-bytes

  * sequence-num

  * start-time

  * stolen-gen2-roots

  * thread-id

  * time

MoarVM::Profile::GCOverview
===========================

An object containing overview information about garbage collections done in this profile.

methods
-------

  * avg-major-time

  * avg-minor-time

  * max-major-time

  * max-minor-time

  * min-major-time

  * min-minor-time

  * total-major

  * total-minor

MoarVM::Profile::Overview
=========================

An object containing overview information about this profile.

Methods
-------

  * first-entry-time

  * parent-thread-id

  * root-node

  * spesh-time

  * thread-id

  * total-time

MoarVM::Profile::Routine
========================

The `MoarVM::Routine` object encapsulates the information about a block that has been executed at least once. A such, the name "Routine" is a bit of a misnomer, "Callable" would have been better probably. But the naming of these modules is following the names of the SQL tables provided, so "Routine" it is.

How the `MoarVM::Routine` object is created, is an implementation detail and as such not documented.

Methods
-------

### id

The numerical ID of the `Callable` in this profile.

### calls

Returns a `List` of `MoarVM::Profile::Call` objects for each call from a different location made to this `Callable`.

### file

The file in which the `Callable` has been defined. Note this can have special path indicators such as "SETTING::" and "NQP::", so there's no direct path to an actual file.

### is-block

Returns `True` if the `Callable` is not a `Routine`.

### is-core

Returns `True` if the `Callable` is part of the Rakudo core.

### is-user

Returns `True` if the `Callable` is user-supplied code.

### line

The line number in which the `Callable` has been defined (if available). **-1** if no line number could be obtained (which is typical of some low level code blocks).

### name

The name of the `Callable`, "(block)" if there is no name, implying this is some type of non-`Routine` `Callable`.

### overview

Returns the `MoarVM:Profile::RoutineOverview` object associated with this `Callable`.

### spesh

Returns the `MoarVM:Profile::SpeshOverview` object associated with this `Callable`, if any.

MoarVM::Profile::RoutineOverview
================================

An object containing some summary information about a `MoarVM::Profile::Routine` object.

Methods
-------

  * deopt-all

  * deopt-one

  * entries

  * exclusive-time

  * id - ID of the associated M:P:Routine object

  * inclusive-time

  * inlined-entries

  * jit-entries

  * osr

  * site-count

  * spesh-entries

MoarVM::Profile::SpeshOverview
==============================

An object containing some spesh related information about a `MoarVM::Profile::Routine` object.

Methods
-------

  * deopt-all

  * deopt-one

  * entries

  * id - ID of the associated M:P:Routine object

  * inlined-entries

  * jit-entries

  * osr

  * sites

  * spesh-entries

MoarVM::Profile::Type
=====================

The `MoarVM::Type` object encapsulates the information about a type (class, enum, subset) that has been accessed at least once.

Methods
-------

### allocations

Returns a `List` with `MoarVM::Profile::Allocation` objects for this type.

### extra-info

A `Map` with extra information about this type.

### id

The numerical ID of the type in this profile.

### name

The name of the this type.

### type-links

A `Map` with extra information about this links to other types.

CREDITS
=======

The SQL used in this module have been mostly copied from the [moarperf](https://github.com/timo/moarperf/blob/master/lib/ProfilerWeb.pm6) repository by *Timo Paulssen*.

AUTHOR
======

Elizabeth Mattijsen <liz@raku.rocks>

COPYRIGHT AND LICENSE
=====================

Copyright 2026 Elizabeth Mattijsen

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

