use v6.*;  # want nano

use DB::SQLite:ver<0.7+>:auth<github:CurtTilmes>:api<1>;
use JSON::Fast:ver<0.19+>:auth<cpan:TIMOTIMO>;

my str @names = "";
my %names = "" => 0;
my sub name2index(str $name) {
    %names{$name} // do {
        my int $index = %names{$name} := @names.elems;
        @names.push($name);
        $index
    }
}

#- DefaultParts ----------------------------------------------------------------
my role DefaultParts {
    has int @.parts is built(:bind);

    multi method new(::?CLASS: @a) {
        self.bless(:parts(my int @parts = @a.map(*.Int)))
    }

    multi method gist(::?CLASS:D:) {
        my str @parts;
        for self.method-names {
            if self."$_"() -> $value {
                @parts.push("$_: $value");
            }
        }
        @parts.join("\n")
    }

    my $columns := $?CLASS.method-names.join(",").trans("-" => "_");
    method columns(::?CLASS:) { $columns }

    my $select := "SELECT $columns FROM $_" with $?CLASS.table;
    method select(::?CLASS:) { $select // Nil }

    my int $index;
    for $?CLASS.method-names -> $name {
        my int $actual = $index++;
        my $method := my method (::?CLASS:D:) { @!parts[$actual] }
        $method.^set_name($name);
        $?CLASS.^add_method($name, $method);
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
        self.bless(:$profile, :parts(
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

    method id(  MoarVM::Profile::Type:D:) {        @!parts[0]  }
    method name(MoarVM::Profile::Type:D:) { @names[@!parts[1]] }

    method extra-info(MoarVM::Profile::Type:D:) {
        ($_ := @!parts[2]) ~~ Str ?? ($_ = from-json($_).Map) !! $_
    }
    method type-links(MoarVM::Profile::Type:D:) {
        ($_ := @!parts[3]) ~~ Str ?? ($_ = from-json($_).Map) !! $_
    }

    multi method gist(MoarVM::Profile::Type:D:) {
        "$.id: $.name $.extra-info"
    }

    method allocations(MoarVM::Profile::Type:D:) {
        $!allocations // do {
            my constant $query = "SELECT "
              ~ MoarVM::Profile::Allocation.columns
              ~ " FROM "
              ~ MoarVM::Profile::Allocation.table
              ~ " WHERE type_id = ?";

            $!allocations := $!profile.db.query($query, self.id).arrays.map({
                MoarVM::Profile::Routine.new(self, $_)
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
    has $!profile;
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

    method allocations(MoarVM::Profile::Call:D:) {
        $!allocations // do {
            my int $id = self.id;
            $!allocations := $!profile.allocations.grep(*.call-id == $id).List
        }
    }

    method parent(MoarVM::Profile::Call:D:) {
        $!profile.calls[self.parent-id] // Nil
    }

    method ancestry(MoarVM::Profile::Call:D:) {
        $!ancestry // do {
            my @parents;
            my @calls := $!profile.calls;
            my $call   = self;
            while @calls[$call.parent-id] -> $parent {
                @parents.unshift($parent);
                $call = $parent;
            }
            $!ancestry := @parents.List
        }
    }
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

    method id(        MoarVM::Profile::Routine:D:) { @!parts[0] }
    method name-index(MoarVM::Profile::Routine:D:) { @!parts[1] }
    method line(      MoarVM::Profile::Routine:D:) { @!parts[2] }
    method file-index(MoarVM::Profile::Routine:D:) { @!parts[3] }

    method name(MoarVM::Profile::Routine:D:) {
        if @!parts[1] -> $index {
            @names[$index]
        }
        else {
            '(block)'
        }
    }
    method file(MoarVM::Profile::Routine:D:) { @names[@!parts[3]] }

    method is-block(MoarVM::Profile::Routine:D:) { @!parts[1] == 0 }

    method is-core(MoarVM::Profile::Routine:D:) {
        self.line < 0 || (self.file andthen .starts-with(
          'SETTING::' | 'NQP::' | 'src/Perl6' | 'src/vm/moar' | 'src/main.nqp'
        ))
    }
    method is-user(MoarVM::Profile::Routine:D:) {
        !self.is-core
    }

    multi method gist(MoarVM::Profile::Routine:D:) {
        "$.id: $.name ($.file:$.line)"
    }

    method overview(MoarVM::Profile::Routine:D:) {
        $!profile.routine-overviews[$.id] // Nil
    }
    method spesh(MoarVM::Profile::Routine:D:) {
        $!profile.spesh-overviews[$.id] // Nil
    }

    method calls(MoarVM::Profile::Routine:D:) {
        $!calls // do {
            my int $id = self.id;
            $!calls := $!profile.calls.grep(*.routine-id == $id).List
        }
    }
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

#- RoutineOverview -------------------------------------------------------------
# SELECT
#   c.routine_id,
#   TOTAL(entries),
#   TOTAL(case WHEN rec_depth = 0 THEN inclusive_time ELSE 0 END),
#   TOTAL(exclusive_time),
#   TOTAL(spesh_entries),
#   TOTAL(jit_entries),
#   TOTAL(inlined_entries),
#   TOTAL(osr),
#   TOTAL(deopt_one),
#   TOTAL(deopt_all),
#   COUNT(c.id)
#  FROM calls c
#  GROUP BY c.routine_id

class MoarVM::Profile::RoutineOverview does DefaultParts {
    method table(--> Nil) { }
    method method-names() is implementation-detail {
        BEGIN <
          id entries inclusive-time exclusive-time spesh-entries jit-entries
          inlined-entries osr deopt-one deopt-all site-count
        >
    }
}

#- SpeshOverview ---------------------------------------------------------------
# SELECT
#   c.routine_id,
#   TOTAL(c.deopt_one),
#   TOTAL(c.deopt_all),
#   TOTAL(c.osr),
#   TOTAL(c.entries),
#   TOTAL(c.inlined_entries),
#   TOTAL(c.spesh_entries),
#   TOTAL(c.jit_entries),
#   COUNT(c.id)
#   FROM calls c
#  WHERE c.deopt_one > 0 OR c.deopt_all > 0 OR c.osr > 0
#  GROUP BY c.routine_id

class MoarVM::Profile::SpeshOverview does DefaultParts {
    method table(--> Nil) { }
    method method-names() is implementation-detail {
        BEGIN <
          id deopt-one deopt-all osr entries inlined-entries spesh-entries
          jit-entries sites
        >
    }
}

#- Profile ---------------------------------------------------------------------
class MoarVM::Profile:ver<0.0.1>:auth<zef:lizmat> {
    has $.db;
    has $!types;
    has $!routines;
    has $!routine-overviews;
    has $!spesh-overviews;
    has $!calls;
    has $!gcs;
    has $!deallocations;

    proto method new(|) {*}
    multi method new(IO() $io where .e && .extension eq 'db') {
        self.bless(:db(DB::SQLite.new(:filename(~$io), |%_)))
    }
    multi method new(IO() $io where .e && .extension eq 'sql', :$create) {
        my $filename := $create ?? ~$io.extension("db") !! "";
        my $db := DB::SQLite.new(:$filename, |%_);
        $db.execute($io.slurp);

        self.bless(:$db)
    }
    multi method new(IO() $io where .e, :$create, :$rerun) {
        my $sql := $*TMPDIR.add(nano ~ ".sql");
        my $db  := $io.extension("db");
        if $db.e {
            if $rerun {
                $db.unlink if $create;
            }
            else {
                return self.new($db, :$create);
            }
        }

        my $proc := run $*EXECUTABLE, "--profile=$sql", $io, :err;
        if $proc.exitcode -> $exit {
            exit $exit;
        }

        my $filename := $create ?? ~$db !! "";
        $db := DB::SQLite.new(:$filename, |%_);
        $db.execute($sql.slurp);
        $sql.unlink;

        self.bless(:$db)
    }
    multi method new(Str:D $code) {
        my $sql := $*TMPDIR.add(nano ~ ".sql");

        my $proc := run $*EXECUTABLE, "--profile=$sql", "-e", $code, :err;
        if $proc.exitcode -> $exit {
            exit $exit;
        }

        my $db := DB::SQLite.new(|%_);
        $db.execute($sql.slurp);

        self.bless(:$db)
    }

    method query(MoarVM::Profile:D: Str:D $query, |c) {
        $!db.query($query, |c)
    }

    method calls(MoarVM::Profile:D:) {
        $!calls // do {
            my @calls is default(Nil);
            for $!db.query(MoarVM::Profile::Call.select).arrays {
                my $call := MoarVM::Profile::Call.new(self, $_);
                @calls[$call.id] := $call;
            }
            $!calls := @calls.List
        }
    }

    method deallocations(MoarVM::Profile:D:) {
        $!deallocations // do {
            $!deallocations := $!db.query(MoarVM::Profile::Deallocation.select).arrays.map({
                MoarVM::Profile::Deallocation.new(self, $_)
            }).List
        }
    }

    method gcs(MoarVM::Profile:D:) {
        $!gcs // do {
            $!routines := $!db.query(MoarVM::Profile::GC.select).arrays.map({
                MoarVM::Profile::GC.new(self, $_)
            }).List
        }
    }

    method routines(MoarVM::Profile:D:) {
        $!routines // do {
            my @routines is default(Nil);
            for $!db.query(MoarVM::Profile::Routine.select).arrays {
                my $routine := MoarVM::Profile::Routine.new(self, $_);
                @routines[$routine.id] := $routine;
            }
            $!routines := @routines.List
        }
    }

    method routine-overviews(MoarVM::Profile:D:) is implementation-detail {
        $!routine-overviews // do {
            my @overviews is default(Nil);
            for $!db.query(q:to/QUERY/).arrays -> @values {
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
QUERY
                my $overview := MoarVM::Profile::RoutineOverview.new(@values);
                @overviews[$overview.id] := $overview;
            }
            $!routine-overviews := @overviews.List
        }
    }

    method spesh-overviews(MoarVM::Profile:D:) is implementation-detail {
        $!spesh-overviews // do {
            my @overviews is default(Nil);
            for $!db.query(q:to/QUERY/).arrays -> @values {
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
QUERY
                my $overview := MoarVM::Profile::SpeshOverview.new(@values);
                @overviews[$overview.id] := $overview;
            }
            $!spesh-overviews := @overviews.List
        }
    }

    method types(MoarVM::Profile:D:) {
        $!types // do {
            my @types is default(Nil);
            for $!db.query(MoarVM::Profile::Type.select).arrays {
                my $type := MoarVM::Profile::Type.new(self, $_);
                @types[$type.id] := $type;
            }
            $!types := @types.List
        }
    }
}

#say MoarVM::Profile::Routine.new( (0,"","",-1) );
#my $profile := MoarVM::Profile.new("bar", :create, :rerun);
#my $profile := MoarVM::Profile.new(q/sub baz($a) { $a * $a }; baz($_) for ^10/);
#.say for $profile.gcs;
#for $profile.routines.grep(*.is-user) {
#    say $_;
#    say .calls.gist.indent(2);
#}
#.say for $profile.spesh-overviews;

# vim: expandtab shiftwidth=4
