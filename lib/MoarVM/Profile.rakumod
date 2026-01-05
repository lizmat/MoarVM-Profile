use v6.*;  # want nano

use DB::SQLite:ver<0.7+>:auth<github:CurtTilmes>:api<1>;
use JSON::Fast:ver<0.19+>:auth<cpan:TIMOTIMO>;

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
            '(block)'
        }
    }
    method file(MoarVM::Profile::Routine:D: --> str) { @names[@!parts[3]] }

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
    method spesh(MoarVM::Profile::Routine:D: --> MoarVM::Profile::SpeshOverview) {
        $!profile.spesh-overviews[$.id] // Nil
    }

    method calls(MoarVM::Profile::Routine:D: --> List:D) {
        $!calls // do {
            my int $id = self.id;
            $!calls := $!profile.calls.grep(*.routine-id == $id).List
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

#- Profile ---------------------------------------------------------------------
class MoarVM::Profile:ver<0.0.1>:auth<zef:lizmat> {
    has $.db;
    has $!overview;
    has $!calls;
    has $!calls-overview;
    has $!deallocations;
    has $!gcs;
    has $!gc-overview;
    has $!routines;
    has $!routine-overviews;
    has $!spesh-overviews;
    has $!types;
    has $!file-ids;

    proto method new(|) {*}
    multi method new(IO:D $io where .e && .extension eq 'db') {
        self.bless(:db(DB::SQLite.new(:filename(~$io), |%_)))
    }
    multi method new(IO:D $io where .e && .extension eq 'sql', :$create) {
        my $filename := $create ?? ~$io.extension("db") !! "";
        my $db := DB::SQLite.new(:$filename, |%_);
        $db.execute($io.slurp);

        self.bless(:$db)
    }
    multi method new(IO:D $io where .e, :$create, :$rerun) {
        my $sql := $*TMPDIR.add(nano ~ ".sql");

        # Run the code, switching off any coverage as that is incompatible
        # with profiling
        my %env = %*ENV;
        %env<MVM_COVERAGE_LOG>:delete;
        my $proc :=
          run $*EXECUTABLE, "--profile=$sql", $io, :err, :%env;
        if $proc.exitcode -> $exit {
            exit $exit;
        }

        my $filename := $create ?? $io.extension("db") !! "";
        my $db := DB::SQLite.new(:$filename, |%_);
        $db.execute($sql.slurp);
        $sql.unlink;

        self.bless(:$db)
    }
    multi method new(Str:D $code, |c) {

        # We can't dispatch properly on IO(), so we catch anything here
        # that looks like a file that needs to be run / loaded
        unless $code.contains(/\s/) {
            return self.new($_, |c) if .e given $code.IO;
        }

        my $sql := $*TMPDIR.add(nano ~ ".sql");

        # Run the code, switching off any coverage as that is incompatible
        # with profiling
        my %env = %*ENV;
        %env<MVM_COVERAGE_LOG>:delete;
        my $proc :=
          run $*EXECUTABLE, "--profile=$sql", "-e", $code, :err, :%env;
        if $proc.exitcode -> $exit {
            exit $exit;
        }

        my $db := DB::SQLite.new(|c);
        $db.execute($sql.slurp);

        self.bless(:$db)
    }

    method query(MoarVM::Profile:D: Str:D $query, |c) {
        CATCH {
            note $query.chomp;
            .rethrow;
        }
#say $query;  # for debugging
        $!db.query($query, |c)
    }

    method overview(MoarVM::Profile:D:) {
        $!overview
          // ($!overview := MoarVM::Profile::Overview.new(
               self.query(MoarVM::Profile::Overview.select).array
             ))
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

    method deallocations(MoarVM::Profile:D: --> List:D) {
        $!deallocations // do {
            $!deallocations := self.query(MoarVM::Profile::Deallocation.select).arrays.map({
                MoarVM::Profile::Deallocation.new(self, $_)
            }).List
        }
    }

    method gcs(MoarVM::Profile:D: --> List:D) {
        $!gcs // do {
            $!gcs := self.query(MoarVM::Profile::GC.select).arrays.map({
                MoarVM::Profile::GC.new($_)
            }).List
        }
    }

    method gc-overview(MoarVM::Profile:D: --> MoarVM::Profile::GCOverview:D) {
        $!gc-overview
          // ($!gc-overview := MoarVM::Profile::GCOverview.new(
               self.query(MoarVM::Profile::GCOverview.select).array
             ))
    }

    method file-ids(MoarVM::Profile:D:) {
        $!file-ids //
          ($!file-ids := self.routines.map(*.file-index).unique.List)
    }

    method routines(MoarVM::Profile:D: --> List:D) {
        if %_ {
            my @routines := self.routines;
            if %_<name> andthen %names{$_} -> int $name-index {
                if %_<file> andthen %names{$_} -> int $file-index {
                    if %_<line> -> int $line {
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
            if %_<file> andthen %names{$_} -> int $index {
                if %_<line> -> int $line {
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

            return ();
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

    method calls-overview(MoarVM::Profile:D:) is implementation-detail {
        $!calls-overview // do {
            $!calls-overview := MoarVM::Profile::CallsOverview.new(
              self.query(MoarVM::Profile::CallsOverview.select).array
            )
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
        $!spesh-overviews // do {
            my @overviews is default(Nil);
            for self.query(MoarVM::Profile::SpeshOverview.select).arrays {
                my $overview := MoarVM::Profile::SpeshOverview.new($_);
                @overviews[$overview.id] := $overview;
            }
            $!spesh-overviews := @overviews.List
        }
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
                return ();
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
}

# vim: expandtab shiftwidth=4
