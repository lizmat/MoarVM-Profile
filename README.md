[![Actions Status](https://github.com/lizmat/MoarVM-Profile/actions/workflows/linux.yml/badge.svg)](https://github.com/lizmat/MoarVM-Profile/actions) [![Actions Status](https://github.com/lizmat/MoarVM-Profile/actions/workflows/macos.yml/badge.svg)](https://github.com/lizmat/MoarVM-Profile/actions) [![Actions Status](https://github.com/lizmat/MoarVM-Profile/actions/workflows/windows.yml/badge.svg)](https://github.com/lizmat/MoarVM-Profile/actions)

NAME
====

MoarVM::Profile - Raku interface to MoarVM profiles

SYNOPSIS
========

```raku
use MoarVM::Profile;
my $profile = MoarVM::Profile(
  'sub foo($a) { $a * $a }; foo($_) for ^1000000'
);

say $profile;
```

    MoarVM Profiler Results at 2026-01-16T21:00:43+01:00
    ================================================================================
    sub foo($a) { $a * $a }; foo($_) for ^1000000

    Time Spent
    ================================================================================
    The profiled code ran for 135.22ms.
    Of this, 29.48ms were spent in garbage collection (that's 21.80%).
    The dynamic optimizer was active for 0.54% of the program's run time.

    Call Frames
    ================================================================================
    In total, 5742 call frames were entered and exited by the profiled code.
    Inlining eliminated the need to create 2996952 call frames (that's 99.81%).
    5293 call frames were interpreted, 2997401 were specialized (99.82%).

    Garbage Collection
    ================================================================================
    The profiled code did 19 garbage collections.
    The average nursery collection time was 1.55ms.
    Scalar replacement eliminated 999137 allocations (that's 33.28%).

    Dynamic Optimization
    ================================================================================
    2997401 optimized frames were seen.
    There was one On Stack Replacement performed.

    157 Routines (showing 5 with most CPU usage)
    ================================================================================
      Entries    Inclusive    Exclusive   Exec  Name
      1000000      33.46%       20.14%   spesh  infix:<*>
                   45.25ms      27.24ms         SETTING::src/core.c/Int.rakumod:348

      1000000      50.10%       16.55%   spesh  foo
                   67.74ms      22.38ms         -e:1

      1000000      65.74%       15.62%   spesh  (block)
                   88.90ms      21.12ms         -e:1

           57       0.28%        0.14%  interp  (block)
                    0.37ms       0.19ms         src/vm/moar/dispatchers.nqp:1125

          166       0.29%        0.13%  interp  find_method
                    0.40ms       0.17ms         src/Perl6/Metamodel/MROBasedMethodDispatch.nqp:13

    24 Types (showing 5 most allocated)
    ================================================================================
    Allocations  Name / Routines
        1999981  Int at 2 call sites:
         999996  infix:<*> SETTING::src/core.c/Int.rakumod:348
         999985  -e:1

            874  Scalar at 7 call sites:
            863  foo -e:1
              3  POPULATE SETTING::src/core.c/Exception.rakumod:1092
              2  backtrace SETTING::src/core.c/Exception.rakumod:10

            580  BOOTCapture at 21 call sites:
            128  NQP::src/core/dispatchers.nqp:5
            122  src/vm/moar/dispatchers.nqp:1452
             76  src/vm/moar/dispatchers.nqp:3431

            463  BOOTTracked at 21 call sites:
             77  src/vm/moar/dispatchers.nqp:3925
             66  src/vm/moar/dispatchers.nqp:3431
             66  NQP::src/core/dispatchers.nqp:273

            451  BOOTHash at 24 call sites:
            332  find_method src/Perl6/Metamodel/MROBasedMethodDispatch.nqp:13
             24  capture SETTING::src/core.c/Parameter.rakumod:297
             16  slurpy SETTING::src/core.c/Parameter.rakumod:288

    19 Garbage Collections (showing 5 slowest)
    ================================================================================
        time seq# F  started  retained  promoted     freed    gen2
      2.84ms    1     3.94ms      18Kb     786Kb    3290Kb    7545 roots

      2.61ms   16   108.07ms       80b              4095Kb      13 roots

      2.02ms    2    11.84ms       80b      18Kb    4077Kb     131 roots

      1.85ms   17   116.64ms       80b              4095Kb      13 roots

      1.52ms   18   124.06ms       80b              4095Kb      13 roots

or use the installed script **mvm-profile**:

    $ mvm-profile 'sub foo($a) { $a * $a }; foo($_) for ^1000000'
    MoarVM Profiler Results at 2026-01-16T21:00:43+01:00
    ================================================================================
    sub foo($a) { $a * $a }; foo($_) for ^1000000

    Time Spent
    ...

DESCRIPTION
===========

The `MoarVM::Profile` distribution provides a Raku interface for the information provided by the MoarVM/Rakudo code profiling information. It is intended to be used in generally applicable applications, but also for ad-hoc profiling situations and benchmarking.

MoarVM::Profile
===============

The main class provided by this distribution is the `MoarVM::Profile` class. Instantiation happens with the `.new` method, which takes one positional argument, and several named arguments.

Positional argument
-------------------

One of the following:

### string with code to be executed

Creates the `MoarVM::Profile` object with the profile information resulting from executing the given code, without creating a permanent SQLite database file.

If the string does not contain any whitespace, and interpreting the string as a path yields a file that exists, then it will be assumed to be a script with executable code.

### path to script to execute

Creates the `MoarVM::Profile` object with the profile information resulting from executing the code in the given `IO::Path`. If the named argument `:create` is specified with a true value, a permanent SQLite database file will be created with the ".db" extension.

### path to pre-generated file with SQL statements (extension: .sql)

Creates the `MoarVM::Profile` object from the pre-generated SQL in the given `IO::Path`. If the named argument `:create` is specified with a true value, a permanent SQLite database file will be created with the ".db" extension.

### path to pre-generated database file (extension: .db)

Creates the `MoarVM::Profile` object from the given SQLite database.

### a `DB::SQLite` object with a profile database

Creates the `MoarVM::Profile` object from the given `DB::SQLite` object.

Named arguments
---------------

### :keep

If specified with a trueish value, will create a permanent copy of the underlying database (if applicable). If the value is a string, then it will be assumed to be the name of the directory in which to store the permanent copy of the database. If a `Bool`, then the current directory will be assumed.

The basename of the database is the number of nano-seconds since epoch. The extension is `.db`.

### :type

The type of profile to make: supported are:

  * profile (default)

Profile all execution, including compilation.

  * profile-compile

Just profile the compilation of the code.

Methods
-------

allocations-overview
--------------------

Returns the `MoarVM::Profile::AllocationsOverview` object associated with this profile.

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

### files

Returns a sorted `List` of "paths" found in this profile. Note these can have special path indicators such as "SETTING::" and "NQP::", so there's no direct path to an actual file (see `.ios`).

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

### ios

Returns a `List` of `IO::Path` objects for all the files, in the same order as the `.files` method.

### names

Returns a sorted `List` of routine names found in this profile.

### overviews

Returns a `List` of `MoarVM::Profile::Overview` objects, one for each thread.

```raku
.say for $profile.overviews;
```

Can also be called with a thread ID, to just return the `MoarVM::Profile::Overview` object for that thread.

```raku
say $profile.overviews[1];
```

### query

Perform a SQL query on the database associated with the profile.

### report

Produce a report about this profile, allowing for these named arguments:

  * :routines - # of routines to show (default: 5)

  * :types - # of types with allocations to show (default: 5)

  * :routines-per-type - # of routines per type (default: 3)

  * :gcs - # of garbage collections (default: 5)

### routines

Returns a `List` of `MoarVM::Profile::Routine` objects, where the index of the object is the same as the `.id` of the object.

```raku
my $routine := $profile.routines[$routine-id];
```

Optionally takes two named arguments:

  * :name - the name to match exactly

  * :file - the name of the file to match exactly

  * :line - the line number in the file to match exactly

```raku
my @routines := $profile.routines(:name<foo>, :file<-e>);
```

Note that this also returns a `List`, as multi subroutines / methods / tokens / rules / regex result in multiple matches.

### target

The target with which this object was created: either a path (string or `IO::Path`), or code to be executed.

### types

Returns a `List` of `MoarVM::Profile::Type` objects, where the index of the object is the same as the `.id` of the object.

```raku
my $type := $profile.types[$type-id];
```

### user-files

Returns a sorted `List` of absolute paths of user files found in this profile.

### user-ios

Returns a `List` of `IO::Path` objects for all the user files, in the same order as the `.user-files` method.

### user-names

Returns a sorted `List` of user routine names found in this profile.

SUBTYPES
========

This distribution provides a number of `MoarVM::Profile::xxx` subtypes who share a number of methods.

Most methods return a native `int`: some obviously do not, such as `.name` and `.file` methods, which return a native `str`.

Methods that indicate a start / end time or interval, are in **nano** seconds.

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

### call-id

ID of the associated `MoarVM::Profile::Call` object.

### count

The number of allocations made for the associated `MoarVM::Profile::Call` and `MoarVM::Profile::Type` object.

### jit

The number of allocations made for the associated `MoarVM::Profile::Call` and `MoarVM::Profile::Type` object while the code in fact was JITted.

### spesh

The number of allocations made for the associated `MoarVM::Profile::Call` and `MoarVM::Profile::Type` object while the code in fact was speshed.

### replaced

The number of allocations that did **not** needed to be made for the associated `MoarVM::Profile::Call` and `MoarVM::Profile::Type` object because a scalar replacement made it unnecessary to do an allocation.

### type-id

ID of the associated `MoarVM::Profile::Type` object.

MoarVM::Profile::AllocationOverview
===================================

An object containing summary information about all calls in this profile.

Methods
-------

  * allocated

  * counted

  * jitted

  * replaced

  * speshed

MoarVM::Profile::Call
=====================

An object containing information about a given call to a `MoarVM::Profile::Routine`.

Methods
-------

  * deopt-all

  * deopt-one

  * entries

  * highest-child-id

  * inlined-entries

  * jit-entries

  * osr

  * rec-depth

  * spesh-entries

### allocations

Returns a `List` with `MoarVM::Profile::Allocation` objects for this routine.

### ancestry

Returns a `List` with `MoarVM::Profile::Call` objects of the parents of this call.

### first-entry-time

The time this call was first made.

### exclusive-time

The number of nano seconds spent in the routine called **without** including the time spent in any calls made inside that routine.

### id

The ID of this call.

### inclusive-time

The number of nano seconds spent in the routine called **including** the time spent in any calls made inside that routine.

### parent

Returns the `MoarVM::Profile::Call` object of the parent of this call, or `Nil` if no parent could be found.

### parent-id

Returns the `id` of the parent of this call.

### routine

The `MoarVM::Profile::Routine` object that was called.

### routine-id

The ID of the `MoarVM::Profile::Routine` object that was called.

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

### type-id

The ID of the `MoarVM::Profile::Type` object that was deallocated.

MoarVM::Profile::GC
===================

An object containing information about a garbage collection run.

Methods
-------

  * cleared-bytes

  * gen2-roots

  * promoted-bytes

  * retained-bytes

  * stolen-gen2-roots

### full

**1** if this was a full garbage collection, else **0**.

### report

Produce a report about this `GC`, accepts these named arguments:

  * bold - bolden if possible (default: not)

  * header - show a header (default: not)

### responsible

The ID of the thread that initiated the garbage collection.

### sequence-num

Basically the ID of this garbage collection (starts at 1).

### start-time

The time this garbage collection was started.

### thread-id

The ID of the thread doing the garbage collection.

### time

The time used to perform the garbage collection.

MoarVM::Profile::GCOverview
===========================

An object containing overview information about garbage collections done in this profile.

methods
-------

### avg-major-time

The average time spent on a full garbage collection (**0** if none were done).

### avg-minor-time

The average time spent on a partial garbage collection (**0** if none were done).

### max-major-time

The maximum time spent on a full garbage collection (**0** if none were done).

### max-minor-time

The maximum time spent on a partial garbage collection (**0** if none were done).

### min-major-time

The minumum time spent on a full garbage collection (**0** if none were done).

### min-minor-time

The minumum time spent on a partial garbage collection (**0** if none were done).

### total-major

The total time spent on full garbage collections (**0** if none were done).

### total-minor

The total time spent on partial garbage collections (**0** if none were done).

MoarVM::Profile::Overview
=========================

An object containing overview information about this profile.

Methods
-------

  * root-node

### first-entry-time

The time profiling was started.

### parent-thread-id

The ID of the thread that initiated (**0** if no parent thread known).

### spesh-time

The amount of time spent by spesh.

### thread-id

The ID of the thread of this information.

### total-time

Total execution time for the program that created this profile.

MoarVM::Profile::Routine
========================

The `MoarVM::Routine` object encapsulates the information about a block that has been executed at least once. A such, the name "Routine" is a bit of a misnomer, "Block" would have been better probably. But the naming of these modules is following the names of the SQL tables provided, so "Routine" it is.

How the `MoarVM::Routine` object is created, is an implementation detail and as such not documented.

Methods
-------

### calls

Returns a `List` of `MoarVM::Profile::Call` objects for each call from a different location made to this `Block`.

### deopt-all

The number of times this `Block` has seen a global de-optimization.

### deopt-one

The number of times this `Block` has seen a local de-optimization.

### entries

The total number of times this `Block` was being called.

### exclusive-time

The time spent in execution of this `Block` alone.

### file

The file in which the `Block` has been defined. Note this can have special path indicators such as "SETTING::" and "NQP::", so there's no direct path to an actual file.

### file-line

Concatenation of the `.file` and `.line` methods with a colon inbetween. Intended to provide a consistent string representation.

### id

The numerical ID of the `Block` in this profile.

### inclusive-time

The time spent in execution of this `Block`, including time spent in any calls that were made in this `Block`.

### inlined-entries

The number of calls that were made with this `Block` inlined.

### io

The normalized `IO::Path` of the file in which this `Block` was defined.

### is-block

Returns `True` if the `Block` is not a `Routine`.

### is-core

Returns `True` if the `Block` is part of the Rakudo core.

### is-user

Returns `True` if the `Block` is user-supplied code.

### jit-entries

The number of calls that were made with this `Block` JITted.

### line

The line number in which the `Block` has been defined (if available). **-1** if no line number could be obtained (which is typical of some low level code blocks).

### lines-around

```raku
say $routine.lines-around;      # 3 lines before / after
say $routine.lines-around(10);  # 10 lines before / after
```

If there is `.source` available, then this will by default return the source code **3** lines before and after the line in which the `Block` begins to be defined. Another number of lines can be specified with the positional argument.

If there is no `.source` available, `Nil` will be returned.

### name

The name of the `Block`, "(block)" if there is no name, implying this is some type of non-`Routine` `Block`.

### name-file-line

Concatenation of the `.name` and `.fileline` methods, with a colon inbetween. Intended to provide a consistent string representation.

### osr

Returns **1** if this `Block` had an Online Stack Replacement.

### report

Produce a report about this `Block`, accepts these named arguments:

  * bold - bolden if possible (default: not)

  * header - show a header (default: not)

### site-count

The number of places from which this `Block` was being called.

### source

Returns the complete source of the file of this `Block` if available. If the profile was created with just code, then that will returned. Else `Nil` will be returned.

### spesh-entries

The number of calls that were made with this `Block` speshed.

MoarVM::Profile::Type
=====================

The `MoarVM::Type` object encapsulates the information about a type (class, enum, subset) that has been accessed at least once.

Methods
-------

### allocated

Returns the total number of allocations done for this type in this profile.

### allocated-by-routine

Returns a `Bag` with the number of allocations done per `MoarVM::Profile::Routine` object.

### allocations

Returns a `Map` with `MoarVM::Profile::Allocation` objects for this type, keyed by their `.call-id`.

### calls

Returns a `List` with `MoarVM::Profile::Call` objects of the `Block`s in which allocations for this type were made.

### count

The total number of allocations made for the this type.

### extra-info

A `Map` with extra information about this type.

### id

The numerical ID of the type in this profile.

### jit

The total number of allocations made for this type while the code in fact was JITted.

### name

The name of the this type.

### replaced

The total number of allocations that did **not** needed to be made for the type because a scalar replacement made it unnecessary to do an allocation.

### report

Produce a report about this `Type`, accepts these named arguments:

  * bold - bolden if possible (default: not)

  * header - show a header (default: not)

### spesh

The total number of allocations made for this type while the code in fact was speshed.

EXPORTED SUBROUTINES
====================

file2io
-------

```raku
say file2io("SETTING::src/core.c/Int.rakumod");
```

Looks at the `file` value (as returned by `MoarVM::Profile::Routine.file` method or the `MoarVM::Profile.files` method) and attempts to convert this to an `IO::Path` of an existing path, taking into account path indicators such as "SETTING::" and "NQP::".

If no valid path is found (like for "-e"), a `Failure` is returned.

CREDITS
=======

The SQL used in this module have been mostly copied from the [moarperf](https://github.com/timo/moarperf/blob/master/lib/ProfilerWeb.pm6) repository by *Timo Paulssen*.

AUTHOR
======

Elizabeth Mattijsen <liz@raku.rocks>

Source can be located at: https://github.com/lizmat/MoarVM-Profile . Comments and Pull Requests are welcome.

If you like this module, or what I'm doing more generally, committing to a [small sponsorship](https://github.com/sponsors/lizmat/) would mean a great deal to me!

COPYRIGHT AND LICENSE
=====================

Copyright 2026 Elizabeth Mattijsen

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

