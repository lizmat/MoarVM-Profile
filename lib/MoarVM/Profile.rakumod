use v6.*;  # want nano

use DB::SQLite:ver<0.7+>:auth<github:CurtTilmes>:api<1>;
use JSON::Fast:ver<0.19+>:auth<cpan:TIMOTIMO>;

#- private subroutines ---------------------------------------------------------
my str @names = "";
my %names = "" => 0;
my sub name2index(str $name --> int) {
    %names{$name} // do {
        my int $index = %names{$name} := @names.elems;
        @names.push($name);
        $index
    }
}

# Because we can't redispatch on a method in a role, the logic for gisting
# is put here in a sub, so that it can get called inside the .gist methods
# of the DefaultParts role, even with the .gist method shadowing the one
# provided by the role.
my sub gist($self --> Str:D) {
    my str @parts;
    for $self.method-names {
        if $self."$_"() -> $value {
            @parts.push("$_: $value");
        }
    }
    @parts.join("\n")
}

# The logic for running code and creating a profile from it, and
# if something went wrong, showing the error (otherwise mute STDERR)
my sub run-code($file, *@args) {

    # Run the code, switching off any coverage as that is incompatible
    # with profiling
    my %env = %*ENV;
    %env<MVM_COVERAGE_LOG>:delete;

    my $proc := run $*EXECUTABLE, "--profile=$file", |@args, :err, :%env;
    if $proc.exitcode -> $exit {

        note $proc.err.slurp.chomp;  # UNCOVERABLE
        exit $exit;  # UNCOVERABLE
    }

    $proc
}

#- exported subroutines --------------------------------------------------------
my $SETTING-root = $*EXECUTABLE.parent(3);
my sub file2io(str $target) is export {
    (my $io := $target.IO).e
      ?? $io
      !! $target.starts-with('SETTING::')
        ?? $SETTING-root.add($target.substr(9))
        !! $target.starts-with('src/main.nqp' | 'src/Perl6' | 'src/vm')
          ?? $SETTING-root.add($target)
          !! $target.starts-with('NQP::')
            ?? $SETTING-root.add("nqp", $target.substr(5))
            !! "Could not normalize '$target' to an existing path".Failure
}

#- DefaultParts ----------------------------------------------------------------
my role DefaultParts {  # UNCOVERABLE
    has int @.parts is built(:bind);

    multi method new(::?CLASS: @a) {
        self.bless(:parts(my int @parts = @a.map({ .defined ?? .Int !! 0 })))
    }

    multi method gist(::?CLASS:D: --> Str:D) { &gist(self) }

    my $columns := $?CLASS.method-names.join(",").trans("-" => "_");
    method columns(::?CLASS:) { $columns }

    my $select := "SELECT $columns FROM $_;" with $?CLASS.table;
    method select(::?CLASS:) { $select // Nil }

    # Add methods for each of the method names provided, each accessing
    # the next element of the @!parts attribute, when the role is being
    # consumed in the class (the mainline of the role is effectively the
    # COMPOSE phaser)
    my int $index;
    for $?CLASS.method-names -> $name {  # UNCOVERABLE

        # Need to create a local copy of the value to be used as index
        # otherwise they will all refer to the highest value seen
        my int $actual = $index++;

        my $method := my method (::?CLASS:D: --> int) { @!parts[$actual] }
        # XXX why doesn't the set_name work?
        $method.^set_name($name);  # UNCOVERABLE
        $?CLASS.^add_method($name, $method);  # UNCOVERABLE
    }
}

#- Allocation ------------------------------------------------------------------
# CREATE TABLE allocations(
#  call_id INT,
#  type_id INT,
#  spesh INT,
#  jit INT,
#  count INT,
#  replaced INT,
#  PRIMARY KEY(call_id, type_id),
#  FOREIGN KEY(call_id) REFERENCES calls(id),
#  FOREIGN KEY(type_id) REFERENCES types(id)
# );

class MoarVM::Profile::Allocation does DefaultParts {
    method table(--> 'allocations') { }
    method method-names() is implementation-detail {
        BEGIN <call-id type-id spesh jit count replaced>
    }
}

#- AllocationsOverview ---------------------------------------------------------
class MoarVM::Profile::AllocationsOverview does DefaultParts {
    method table(--> 'allocations') { }
    method method-names() is implementation-detail {
        BEGIN <counted speshed jitted allocated replaced> 
    }
    method select(--> Str:D) { q:to/SQL/ }
SELECT
  total(count),
  total(spesh),
  total(jit),
  total(count + spesh + jit),
  total(replaced)
  FROM allocations
SQL
}

#- Overview --------------------------------------------------------------------
# CREATE TABLE profile(
#  total_time INT,
#  spesh_time INT,
#  thread_id INT,
#  parent_thread_id INT,
#  root_node INT,
#  first_entry_time INT,
#  FOREIGN KEY(root_node) REFERENCES calls(id)
# );

class MoarVM::Profile::Overview does DefaultParts {
    method table(--> 'profile') { }
    method method-names() is implementation-detail {
        BEGIN <
          total-time spesh-time thread-id parent-thread-id
          root-node first-entry-time
        >
    }
}

#- Type ------------------------------------------------------------------------
# CREATE TABLE types(
#  id INTEGER PRIMARY KEY ASC,
#  name TEXT,
#  extra_info JSON,
#  type_links JSON
# );
class MoarVM::Profile::Type {
    has $.profile;
    has @.parts is built(:bind);
    has $!allocations;

    multi method new(MoarVM::Profile::Type: $profile, @a) {
        self.bless(:$profile, :parts(  # UNCOVERABLE
          (@a[0].Int, name2index(@a[1]), @a[2], @a[3])
        ))
    }

    method table(--> 'types') { }
    method method-names() is implementation-detail {
        BEGIN <id name extra-info type-links>
    }
    method columns() {
        BEGIN $?CLASS.method-names.join(",").trans("-" => "_")
    }
    method select() {
        BEGIN "SELECT " ~ $?CLASS.columns ~ " FROM " ~ $?CLASS.table
    }

    method id(        MoarVM::Profile::Type:D: --> int) { @!parts[0] }
    method name-index(MoarVM::Profile::Type:D: --> int) { @!parts[1] }

    method name(MoarVM::Profile::Type:D:) { @names[@!parts[1]] }

    method extra-info(MoarVM::Profile::Type:D:) {
        ($_ := @!parts[2]) ~~ Str ?? ($_ = from-json($_).Map) !! $_
    }
    method type-links(MoarVM::Profile::Type:D:) {
        ($_ := @!parts[3]) ~~ Str ?? ($_ = from-json($_).Map) !! $_
    }

    multi method gist(MoarVM::Profile::Type:D: --> Str:D) {
        "$.id: $.name $.extra-info"
    }

    method allocations(MoarVM::Profile::Type:D: --> List:D) {
        $!allocations // do {
            my constant $query = "SELECT "
              ~ MoarVM::Profile::Allocation.columns
              ~ " FROM "
              ~ MoarVM::Profile::Allocation.table
              ~ " WHERE type_id = ?";

            $!allocations := $!profile.query($query, self.id).arrays.map({
                MoarVM::Profile::Allocation.new($_)
            }).List
        }
    }
}

#- Call ------------------------------------------------------------------------
# CREATE TABLE calls(
#  id INTEGER PRIMARY KEY ASC,
#  parent_id INT,
#  routine_id INT,
#  osr INT,
#  spesh_entries INT,
#  jit_entries INT,
#  inlined_entries INT,
#  inclusive_time INT,
#  exclusive_time INT,
#  entries INT,
#  deopt_one INT,
#  deopt_all INT,
#  rec_depth INT,
#  first_entry_time INT,
#  highest_child_id INT,
#  FOREIGN KEY(routine_id) REFERENCES routines(id)
# );

class MoarVM::Profile::Call does DefaultParts {
    has $.profile;
    has $!allocations;
    has $!ancestry;

    multi method new(MoarVM::Profile::Call: $profile, @a) {
        self.bless(:$profile, :parts(my int @parts = @a.map(*.Int)))
    }

    method table(--> 'calls') { }
    method method-names() is implementation-detail {
        BEGIN <
          id parent-id routine-id osr spesh-entries inlined-entries
          inclusive-time exclusive-time entries deopt-one deopt-all
          rec-depth first-entry-time highest-child-id
        >
    }

    method allocations(MoarVM::Profile::Call:D: --> List:D) {
        $!allocations // do {
            my constant $query = "SELECT "
              ~ MoarVM::Profile::Allocation.columns
              ~ " FROM "
              ~ MoarVM::Profile::Allocation.table
              ~ " WHERE call_id = ?";

            $!allocations := $!profile.query($query, self.id).arrays.map({
                MoarVM::Profile::Allocation.new($_)
            }).List
        }
    }

    method parent(MoarVM::Profile::Call:D: --> MoarVM::Profile::Call:D) {
        my int $parent-id = self.parent-id;
        $!profile.calls.first(*.id == $parent-id)
    }

    method ancestry(MoarVM::Profile::Call:D: --> List) {
        $!ancestry // do {
            my @parents;
            my @calls := $!profile.calls;
            my $call   = self;
            while $call.parent-id -> int $id {
                my $parent := @calls[$id];
                @parents.unshift($parent);
                $call = $parent;
            }
            @parents.unshift(@calls.head);
            $!ancestry := @parents.List
        }
    }
}

#- CallsOverview -------------------------------------------------------------
class MoarVM::Profile::CallsOverview does DefaultParts {
    method table(--> 'calls') { }
    method method-names() is implementation-detail {
        BEGIN <
          entries-total spesh-entries-total jit-entries-total
          inlined-entries-total deopt-one-total deopt-all-total
          osr-total
        >
    }
    method select(--> Str:D) { q:to/SQL/ }
SELECT
  total(entries),
  total(spesh_entries),
  total(jit_entries),
  total(inlined_entries),
  total(deopt_one),
  total(deopt_all),
  total(osr)
  FROM calls
SQL
}

#- GC --------------------------------------------------------------------------
# CREATE TABLE gcs(
#  time INT,
#  retained_bytes INT,
#  promoted_bytes INT,
#  gen2_roots INT,
#  stolen_gen2_roots INT,
#  full INT,
#  responsible INT,
#  cleared_bytes INT,
#  start_time INT,
#  sequence_num INT,
#  thread_id INT,
#  PRIMARY KEY(sequence_num, thread_id)
# );

class MoarVM::Profile::GC does DefaultParts {
    method table(--> 'gcs') { }
    method method-names() is implementation-detail {
        BEGIN <
          time retained-bytes promoted-bytes gen2-roots stolen-gen2-roots
          full responsible cleared-bytes start-time sequence-num thread-id
        >
    }
}

#- GCOverview ------------------------------------------------------------------
class MoarVM::Profile::GCOverview does DefaultParts {
    method table(--> 'gcs') { }
    method method-names() is implementation-detail {
        BEGIN <
          avg-minor-time min-minor-time max-minor-time
          avg-major-time min-major-time max-major-time
          total-minor total-major
        >
    }
    method select(--> Str:D) { q:to/SQL/ }
SELECT
  AVG(  CASE WHEN full == 0 THEN latest_end - earliest END),
  MIN(  CASE WHEN full == 0 THEN latest_end - earliest END),
  MAX(  CASE WHEN full == 0 THEN latest_end - earliest END),
  AVG(  CASE WHEN full == 1 THEN latest_end - earliest END),
  MIN(  CASE WHEN full == 1 THEN latest_end - earliest END),
  MAX(  CASE WHEN full == 1 THEN latest_end - earliest END),
  TOTAL(CASE WHEN full == 0 THEN latest_end - earliest END),
  TOTAL(CASE WHEN full == 1 THEN latest_end - earliest END),
  TOTAL(latest_end - earliest)
FROM (SELECT
        MIN(start_time)        AS earliest,
        MAX(start_time + time) AS latest_end,
        full
FROM gcs
  GROUP BY sequence_num
  ORDER BY sequence_num ASC)
SQL
    multi method gist(MoarVM::Profile::GCOverview:D: --> Str:D) {
        self.total-minor ?? gist(self) !! "(no garbage collections done)"
    }

    method total(MoarVM::Profile::GCOverview:D: --> int) {
        self.total-minor + self.total-major
    }
}

#- RoutineOverview -------------------------------------------------------------
class MoarVM::Profile::RoutineOverview does DefaultParts {
    method table(--> 'calls') { }
    method method-names() is implementation-detail {
        BEGIN <
          id entries inclusive-time exclusive-time spesh-entries jit-entries
          inlined-entries osr deopt-one deopt-all site-count
        >
    }
    method select(--> Str:D) { q:to/SQL/ }
SELECT
  c.routine_id,
  TOTAL(entries),
  TOTAL(case WHEN rec_depth = 0 THEN inclusive_time ELSE 0 END),
  TOTAL(exclusive_time),
  TOTAL(spesh_entries),
  TOTAL(jit_entries),
  TOTAL(inlined_entries),
  TOTAL(osr),
  TOTAL(deopt_one),
  TOTAL(deopt_all),
  COUNT(c.id)
FROM calls c
GROUP BY c.routine_id
SQL
}

#- SpeshOverview ---------------------------------------------------------------
class MoarVM::Profile::SpeshOverview does DefaultParts {
    method table(--> 'calls') { }
    method method-names() is implementation-detail {
        BEGIN <
          id deopt-one deopt-all osr entries inlined-entries spesh-entries
          jit-entries sites
        >
    }
    method select(--> Str:D) { q:to/SQL/ }
SELECT
  c.routine_id,
  TOTAL(c.deopt_one),
  TOTAL(c.deopt_all),
  TOTAL(c.osr),
  TOTAL(c.entries),
  TOTAL(c.inlined_entries),
  TOTAL(c.spesh_entries),
  TOTAL(c.jit_entries),
  COUNT(c.id)
FROM calls c
WHERE c.deopt_one > 0 OR c.deopt_all > 0 OR c.osr > 0
GROUP BY c.routine_id
SQL
}

#- Routine ---------------------------------------------------------------------
# CREATE TABLE routines(
#  id INTEGER PRIMARY KEY ASC,
#  name TEXT,
#  line INT,
#  file TEXT
# );

class MoarVM::Profile::Routine {
    has int @!parts is built(:bind);
    has     $.profile;
    has     $!calls;

    multi method new(MoarVM::Profile::Routine: $profile, @a) {
        self.bless(:$profile, :parts(
          my int @parts =
            @a[0].Int, name2index(@a[1]), @a[2].Int, name2index(@a[3])
        ))
    }

    method table(--> 'routines') { }
    method method-names() is implementation-detail {
        BEGIN <id name line file>
    }
    method columns() {
        BEGIN $?CLASS.method-names.join(",").trans("-" => "_")
    }
    method select() is implementation-detail {
        BEGIN "SELECT " ~ $?CLASS.columns ~ " FROM " ~ $?CLASS.table
    }

    method id(        MoarVM::Profile::Routine:D: --> int) { @!parts[0] }
    method name-index(MoarVM::Profile::Routine:D: --> int) { @!parts[1] }
    method line(      MoarVM::Profile::Routine:D: --> int) { @!parts[2] }
    method file-index(MoarVM::Profile::Routine:D: --> int) { @!parts[3] }

    method name(MoarVM::Profile::Routine:D: --> str) {
        if @!parts[1] -> $index {
            @names[$index]
        }
        else {
            '(block)'  # UNCOVERABLE
        }
    }
    method file(MoarVM::Profile::Routine:D: --> str ) { @names[@!parts[3]] }
    method io(  MoarVM::Profile::Routine:D: --> IO:D) { file2io self.file  }

    method is-block(MoarVM::Profile::Routine:D: --> Bool:D) { @!parts[1] == 0 }

    method is-core(MoarVM::Profile::Routine:D: --> Bool:D) {
        (self.line < 0 || (self.file andthen .starts-with(
          'SETTING::' | 'NQP::' | 'src/Perl6' | 'src/vm/moar' | 'src/main.nqp'
        ))).Bool
    }
    method is-user(MoarVM::Profile::Routine:D: --> Bool:D) {
        !self.is-core
    }

    multi method gist(MoarVM::Profile::Routine:D: --> Str:D) {
        "$.id: $.name ($.file:$.line)"
    }

    method overview(MoarVM::Profile::Routine:D: --> MoarVM::Profile::RoutineOverview:D) {
        $!profile.routine-overviews[$.id] // Nil
    }

    method calls(MoarVM::Profile::Routine:D: --> List:D) {
        $!calls // do {
            my int $id = self.id;
            $!calls := $!profile.calls.grep(*.routine-id == $id).List
        }
    }

    method source(MoarVM::Profile::Routine:D:) {
        if self.io -> $io {
            $io.slurp
        }
        else {
            (my $target := $!profile.target) ~~ IO::Path
              ?? Nil   # either .sql or .db without known source
              !! $target
        }
    }

    method lines-around(MoarVM::Profile::Routine:D: int $extra = 3) {
        if self.source -> $source {
            my @lines = $source.lines(:!chomp);
            my int $line = $.line;
            my int $from = $line - $extra max 1;
            my int $to   = $line + $extra min +@lines;
            
            ($from .. $to).map(-> $line {
                "$line.fmt("\%$to.chars()d") @lines[$line - 1]"
            }).join
        }
        else {
            Nil
        }
    }
}

#- Deallocation ----------------------------------------------------------------
# CREATE TABLE deallocations(
#  gc_seq_num INT,
#  gc_thread_id INT,
#  type_id INT,
#  nursery_fresh INT,
#  nursery_seen INT,
#  gen2 INT,
#  PRIMARY KEY(gc_seq_num, gc_thread_id, type_id),
#  FOREIGN KEY(gc_seq_num, gc_thread_id) REFERENCES gcs(sequence_num,thread_id),
#  FOREIGN KEY(type_id) REFERENCES types(id)
# );
class MoarVM::Profile::Deallocation does DefaultParts {
    method table(--> 'deallocations') { }
    method method-names() is implementation-detail {
        BEGIN <
          gc-seq-num gc-thread-id type-id nursery-fresh nursery-seen gen2
        >
    }
}

#- Profile creation ------------------------------------------------------------
class MoarVM::Profile:ver<0.0.4>:auth<zef:lizmat> {
    has $.target;
    has $.db;
    has $!overviews;
    has $!calls;
    has $!calls-overview;
    has $!allocations-overview;
    has $!deallocations;
    has $!gcs;
    has $!gc-overview;
    has $!routines;
    has $!routine-overviews;
    has $!spesh-overviews;
    has $!types;
    has $!files;
    has $!ios;
    has $!names;
    has $!user-files;
    has $!user-ios;
    has $!user-names;

    proto method new(|) {*}
    multi method new(IO:D $target where .e && .extension eq 'db') {
        self.bless(:$target, :db(DB::SQLite.new(:filename(~$target), |%_)))
    }
    multi method new(IO:D $target where .e && .extension eq 'sql', :$create) {
        my $filename := $create ?? ~$target.extension("db") !! "";
        my $db := DB::SQLite.new(:$filename, |%_);
        $db.execute($target.slurp);

        self.bless(:$target, :$db)
    }
    multi method new(IO:D $target where .e, :$create, :$actual-target) {
        my $sql := $*TMPDIR.add(nano ~ ".sql");

        my $proc     := run-code($sql, $target);
        my $filename := $create ?? $target.extension("db") !! "";
        my $db := DB::SQLite.new(:$filename, |%_);
        $db.execute($sql.slurp);
        $sql.unlink;

        self.bless(:target($actual-target // $target), :$db)
    }
    multi method new(Str:D $target, |c) {

        # We can't dispatch properly on IO(), so we catch anything here
        # that looks like a file that needs to be run / loaded
        unless $target.contains(/\s/) {
            return self.new($_, |c, :actual-target($target))
              if .e given $target.IO;
        }

        my $sql  := $*TMPDIR.add(nano ~ ".sql");
        my $proc := run-code($sql, "-e", $target);
        my $db   := DB::SQLite.new(|c);
        $db.execute($sql.slurp);

        self.bless(:$target, :$db)
    }

    method !map-routines(&mapper) { self.routines.map(&mapper).unique.List }

#- Profile methods -------------------------------------------------------------
    method allocations-overview(MoarVM::Profile:D:) {
        $!allocations-overview // ($!allocations-overview :=
          MoarVM::Profile::AllocationsOverview.new(
            self.query(MoarVM::Profile::AllocationsOverview.select).array
          )
        )
    }

    method calls(MoarVM::Profile:D: --> List:D) {
        $!calls // do {
            my @calls is default(Nil);
            for self.query(MoarVM::Profile::Call.select).arrays {
                my $call := MoarVM::Profile::Call.new(self, $_);
                @calls[$call.id] := $call;
            }
            $!calls := @calls.List
        }
    }

    method calls-overview(MoarVM::Profile:D:) {
        $!calls-overview // ($!calls-overview :=
          MoarVM::Profile::CallsOverview.new(
            self.query(MoarVM::Profile::CallsOverview.select).array
          )
        )
    }

    method deallocations(MoarVM::Profile:D: --> List:D) {
        $!deallocations // ($!deallocations :=
          self.query(MoarVM::Profile::Deallocation.select).arrays.map({
              MoarVM::Profile::Deallocation.new($_)
          }).eager)
    }

    method gcs(MoarVM::Profile:D: --> List:D) {
        $!gcs // ($!gcs :=
          self.query(MoarVM::Profile::GC.select).arrays.map({
              MoarVM::Profile::GC.new($_)
          }).eager)
    }

    method gc-overview(MoarVM::Profile:D: --> MoarVM::Profile::GCOverview:D) {
        $!gc-overview // ($!gc-overview := MoarVM::Profile::GCOverview.new(
          self.query(MoarVM::Profile::GCOverview.select).array
        ))
    }

    multi method gist(MoarVM::Profile:D: :$bold --> Str:D) {
        my str $BON  = $bold ?? "\e[1m"  !! "";
        my str $BOFF = $bold ?? "\e[22m" !! "";

        # Bold some texts if so indicated
        my sub bold(Str() $text) { $BON ~ $text ~ $BOFF }

        # Convert nano-seconds to milliseconds
        my sub milli(Str() $nano) {
            "$BON$nano.substr(0,*-3)\.$nano.substr(*-3,2)ms$BOFF"
        }

        # Convert to Rat to percentage
        my sub percent(Rat:D $rat) {
            $rat
              ?? sprintf("$BON%.2f%%$BOFF", 100 * $rat)
              !! $BON ~ "0%" ~ $BOFF
        }

        # Convert an Instant to a readable DateTime
        my sub datetime(Instant:D $then) {
            $then.DateTime.Str.subst(/ \.\d+ /)
        }

        my $overview   := self.overviews(1);
        my $total-time := $overview.total-time;
        my $spesh-time := $overview.spesh-time;

        my $gc-overview   := self.gc-overview;
        my $total-gc-time := $gc-overview.total;

        my $calls-overview    := self.calls-overview;
        my $calls-total       := $calls-overview.entries-total;
        my $spesh-total       := $calls-overview.spesh-entries-total;
        my $inlined-total     := $calls-overview.inlined-entries-total;
        my $jit-total         := $calls-overview.jit-entries-total;
        my $entered-total     := $calls-total - $inlined-total;
        my $interpreted-total := $calls-total - $spesh-total;
        my $spesh-jit-total   := $spesh-total + $jit-total;
        my $osr-total         := $calls-overview.osr-total;
        my $deopt-one-total   := $calls-overview.deopt-one-total;
        my $deopt-all-total   := $calls-overview.deopt-all-total;

        my $gcs := self.gcs;

        my $allocations-overview := self.allocations-overview;
        my $replaced  := $allocations-overview.replaced;
        my $allocated := $allocations-overview.allocated - $replaced;

        my str @parts;
        my sub add(str $text) { @parts.push($text) }

        add "MoarVM Profiler Results";
        add "=======================";
        add $!target ~~ IO
          ?? $!target.extension eq 'db' | 'sql'
            ?? "&bold($!target) (created &datetime($!target.created))"
            !! "&bold($!target) (changed &datetime($!target.changed))"
          !! bold($!target);

        add "";
        add "Time Spent";
        add "==========";
        add "The profiled code ran for &milli($total-time).";
        add "Of this, &milli($total-gc-time) were spent in garbage collection (that's &percent($total-gc-time / $total-time)).";
        add "The dynamic optimizer was active for &percent($spesh-time / $total-time) of the program's run time.";

        add "";
        add "Call Frames";
        add "===========";
        add "In total, &bold("$entered-total call frames") were entered and exited by the profiled code.";
        add "Inlining eliminated the need to create &bold("$inlined-total call frames") (that's &percent($inlined-total / $calls-total)).";
        add "&bold($interpreted-total) call frames were interpreted, &bold($spesh-total) were specialized (&percent($spesh-total / $calls-total)).";

        add "";
        add "Garbage Collection";
        add "==================";
        add "The profiled code did &bold("$gcs.elems() garbage collections").";
        add "There were &bold("$gcs.grep(*.full).elems() full collections") involving the entire heap.";
        add "The average nursery collection time was &milli($gc-overview.avg-minor-time).";
        add "Scalar replacement eliminated &bold($replaced) allocations (that's &percent($replaced / $allocated)).";

        add "";
        add "Dynamic Optimization";
        add "====================";
        add "Of $spesh-jit-total optimized frames, there were &bold("$deopt-one-total deoptimizations") (that's &percent($deopt-one-total / $spesh-jit-total)).";
        add $deopt-all-total
          ?? $deopt-all-total == 1
            ?? "There was &bold("one global deoptimization")."
            !! "There were &bold("$deopt-all-total global deoptimizations")."
          !! "There was &bold("no global deoptimization") triggered.";
        add $osr-total == 1
          ?? "There was &bold("one On Stack Replacement") performed."
          !! "There were &bold("$osr-total On Stack Replacements") performed.";

        add "";
        @parts.join("\n")
    }

    method files(MoarVM::Profile:D:) {
        $!files // ($!files := @names[self!map-routines({
            if .file-index -> $index { $index }
        })].sort(*.fc).List)
    }

    method ios(MoarVM::Profile:D:) {
        $!ios // ($!ios := self.files.map(&file2io).List)
    }

    method names(MoarVM::Profile:D:) {
        $!names // ($!names := @names[self!map-routines({
            if .name-index -> $index { $index }
        })].sort(*.fc).List)
    }

    method overviews(MoarVM::Profile:D: $thread-id?) {
        with $thread-id {
            self.overviews.first(*.thread-id == $thread-id)
        }
        else {
            $!overviews // ($!overviews :=
              self.query(MoarVM::Profile::Overview.select).arrays.map({
                  MoarVM::Profile::Overview.new($_)
              }).eager)
        }
    }

    method query(MoarVM::Profile:D: Str:D $query, |c) {
        CATCH {
            note $query.chomp;
            .rethrow;
        }
#say $query;  # for debugging
        $!db.query($query, |c)
    }

    method routines(MoarVM::Profile:D: --> List:D) {
        if %_ {
            my @routines := self.routines;
            if %_<name>:delete andthen %names{$_} -> int $name-index {
                if %_<file>:delete andthen %names{$_} -> int $file-index {
                    if %_<line>:delete -> int $line {
                        return @routines.grep({
                            .defined
                              && .name-index == $name-index
                              && .file-index == $file-index
                              && .line       == $line
                        }).List;
                    }
                    else {
                        return @routines.grep({
                            .defined
                              && .name-index == $name-index
                              && .file-index == $file-index
                        }).List;
                    }
                }
                else {
                    return @routines.grep({
                        .defined && .name-index == $name-index
                    }).List;
                }
            }
            if %_<file>:delete andthen %names{$_} -> int $index {
                if %_<line>:delete -> int $line {
                    return @routines.grep({
                        .defined && .file-index == $index && .line == $line
                    }).List;
                }
                else {
                    return @routines.grep({
                        .defined && .file-index == $index
                    }).List;
                }
            }

            %_
              ?? (die "Unhandled combination of arguments: %_.raku()")
              !! return ()
        }

        $!routines // do {
            my @routines is default(Nil);
            for self.query(MoarVM::Profile::Routine.select).arrays {
                my $routine := MoarVM::Profile::Routine.new(self, $_);
                @routines[$routine.id] := $routine;
            }
            $!routines := @routines.List
        }
    }

    method routine-overviews(MoarVM::Profile:D:) is implementation-detail {
        $!routine-overviews // do {
            my @overviews is default(Nil);
            for self.query(MoarVM::Profile::RoutineOverview.select).arrays {
                my $overview := MoarVM::Profile::RoutineOverview.new($_);
                @overviews[$overview.id] := $overview;
            }
            $!routine-overviews := @overviews.List
        }
    }

    method spesh-overviews(MoarVM::Profile:D:) is implementation-detail {
        $!spesh-overviews // ($!spesh-overviews :=
          self.query(MoarVM::Profile::SpeshOverview.select).arrays.map({
              MoarVM::Profile::SpeshOverview.new($_);
          }).eager)
    }

    method types(MoarVM::Profile:D: --> List:D) {
        if %_ {
            my @types := self.types;
            if %_<name> andthen %names{$_} -> int $name-index {
                return @types.grep({
                    .defined && .name-index == $name-index
                }).List
            }
            else {
                die "Unhandled combination of arguments: %_.raku()";
            }
        }

        $!types // do {
            my @types is default(Nil);
            for self.query(MoarVM::Profile::Type.select).arrays {
                my $type := MoarVM::Profile::Type.new(self, $_);
                @types[$type.id] := $type;
            }
            $!types := @types.List
        }
    }

    method user-files(MoarVM::Profile:D:) {
        $!user-files // ($!user-files := @names[self!map-routines({
            if .is-user && .file-index -> $index { $index }
        })].sort(*.fc).List)
    }

    method user-ios(MoarVM::Profile:D:) {
        $!user-ios // ($!user-ios := self.user-files.map(&file2io).List)
    }

    method user-names(MoarVM::Profile:D:) {
        $!user-names // ($!user-names := @names[self!map-routines({
            if .is-user && .name-index -> $index { $index }
        })].sort(*.fc).List)
    }
}

# vim: expandtab shiftwidth=4
