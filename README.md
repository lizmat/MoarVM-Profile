[![Actions Status](https://github.com/lizmat/MoarVM-Profile/actions/workflows/linux.yml/badge.svg)](https://github.com/lizmat/MoarVM-Profile/actions) [![Actions Status](https://github.com/lizmat/MoarVM-Profile/actions/workflows/macos.yml/badge.svg)](https://github.com/lizmat/MoarVM-Profile/actions) [![Actions Status](https://github.com/lizmat/MoarVM-Profile/actions/workflows/windows.yml/badge.svg)](https://github.com/lizmat/MoarVM-Profile/actions)

NAME
====

MoarVM::Profile - Raku interface to MoarVM profiles

SYNOPSIS
========

```raku
use MoarVM::Profile;
```

DESCRIPTION
===========

The `MoarVM::Profile` distribution provides a Raku interface for the information provided by the MoarVM/Rakudo code profiling information. It is intended to be used in generally applicable applications, but also for ad-hoc profiling situations and benchmarking.

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

