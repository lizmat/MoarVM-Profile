use v6.*;  # want nano

use DB::SQLite:ver<0.7+>:auth<github:CurtTilmes>:api<1>;
use JSON::Fast:ver<0.19+>:auth<cpan:TIMOTIMO>;  # from-json

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
my sub run-code($file, *@args, :$type = 'profile') {

    # Run the code, switching off any coverage as that is incompatible
    # with profiling
    my %env = %*ENV;
    %env<MVM_COVERAGE_LOG>:delete;

    my $proc := run $*EXECUTABLE, "--$type=$file", |@args, :err, :%env;
    if $proc.exitcode -> $exit {

        note $proc.err.slurp.chomp;  # UNCOVERABLE
        exit $exit;  # UNCOVERABLE
    }

    $proc
}

my constant $BON  = "\e[1m";
my constant $BOFF = "\e[22m";

# Bold some texts (or not)
my sub bold( Str() $text) { $BON ~ $text ~ $BOFF }  # UNCOVERABLE
my sub plain(Str() $text) {        $text         }  # UNCOVERABLE

# Convert nano-seconds to milliseconds
my sub milli(int $nano, $width? is copy) {
    --$width if $width;
    my $milli := $nano < 5
      ?? $width
        ?? (" " x --$width) ~ "0ms"
        !! "0ms"
      !! sprintf(($width ?? "%$width.2fms" !! "%.2fms"), $nano / 1000);
    $*BOLD ?? bold($milli) !! $milli
}

# Convert to Rat to percentage
my sub percent(Rat:D $rat, $width = "") {
    my $percent := $rat
      ?? sprintf("%$width.2f%%", 100 * $rat)
      !! sprintf("%{$width + 1}s", "0%");  # UNCOVERABLE
    $*BOLD ?? bold($percent) !! $percent
}

# Convert an Instant to a readable DateTime
my sub datetime(Instant:D $then) {
    $then.DateTime.Str.subst(/ \.\d+ /)
}

# Convert a bytes value into appropriate string
my sub bytes(int $bytes) {
    $bytes  # UNCOVERABLE
      ?? $bytes < 1024
        ?? $bytes ~ "b"
        !! $bytes < 10 * 1024 * 1024
          ?? ($bytes div 1024) ~ "Kb"
          !! ($bytes div (1024 * 1024)) ~ "Mb"
      !! ""
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

    multi method gist(::?CLASS:D: --> Str:D) {
        self.?report(:header) // &gist(self)
    }

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
    has int @!parts      is built(:bind);
    has     $!profile    is built(:bind);
    has     $!extra-info is built;;
    has     $!type-links is built;;
    has     $!calls;
    has     $!allocations;
    has     $!allocated;
    has     $!allocated-by-routine;

    multi method new(MoarVM::Profile::Type: $profile, @a) {
        self.bless(
          :$profile,
          :parts(my int @ = @a[0].Int, name2index(@a[1])),
          :extra-info(@a[2]),
          :type-links(@a[3])
        )
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
        ($_ := $!extra-info) ~~ Str ?? ($_ = from-json($_).Map) !! $_
    }
    method type-links(MoarVM::Profile::Type:D:) {
        ($_ := $!type-links) ~~ Str ?? ($_ = from-json($_).Map) !! $_
    }

    # From .add-overview
    method spesh(   MoarVM::Profile::Type:D: --> int) { @!parts[2] }
    method jit(     MoarVM::Profile::Type:D: --> int) { @!parts[3] }
    method count(   MoarVM::Profile::Type:D: --> int) { @!parts[4] }
    method replaced(MoarVM::Profile::Type:D: --> int) { @!parts[5] }

    # This adds the overview information from the calls table to the
    # object, so that they can be accessed quickly in selecting and
    # sorting operations
    method add-overview(MoarVM::Profile::Type:D: @values
    --> Nil) is implementation-detail {
        @!parts.append(@values.map(*.Int))
    }

    method report(MoarVM::Profile::Type:D:
      Bool() :$bold,
      Bool() :$header,
      Int:D  :$limit = 5,
    --> Str:D) {
        my &bold       = $bold ?? &UNIT::bold !! &plain;
        my %allocated := self.allocated-by-routine;

        my str @parts;
        my sub add(str $text) { @parts.push($text) }

        add "Allocations  Name / Routines\n" if $header;
        add "&bold(self.allocated.fmt('%11d'))  &bold(self.name) at ";

        if %allocated.elems > 1 {
            add "&bold(%allocated.elems()) call sites:\n";
            for %allocated.sort(-*.value).head($limit) {
                add "&bold(.value.fmt('%11d'))  $_.key.name-file-line(:$bold)\n";
            }
        }
        else {
            add "%allocated.head.key.file-line()\n";
        }

        @parts.join
    }

    multi method gist(MoarVM::Profile::Type:D: --> Str:D) {
        self.report(:header)
    }

    method allocated-by-routine(MoarVM::Profile::Type:D: --> Bag:D) {
        $!allocated-by-routine // do {
            my %allocations := self.allocations;
            my @routines    := $!profile.routines;

            $!allocated-by-routine := self.calls.map({
                @routines[.routine-id] => %allocations{.id}.count
            }).Bag
        }
    }

    method calls(MoarVM::Profile::Type:D: --> List:D) {
        $!calls // ($!calls := $!profile.calls[self.allocations.keys].List)
    }

    method allocated(MoarVM::Profile::Type:D: --> Int:D) {
        $!allocated // ($!allocated := self.allocations.values.map(*.count).sum)
    }

    method allocations(MoarVM::Profile::Type:D: --> Map:D) {
        $!allocations // do {
            my constant $query = "SELECT "
              ~ MoarVM::Profile::Allocation.columns
              ~ " FROM "
              ~ MoarVM::Profile::Allocation.table
              ~ " WHERE type_id = ?";

            $!allocations := my %allocations is Map =
              $!profile.query($query, self.id).arrays.map: {
                .head => MoarVM::Profile::Allocation.new($_)
            }
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
    has $!profile is built;
    has $!routine;
    has $!allocations;
    has $!allocated;
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

    method routine(MoarVM::Profile::Call:D:) {
        $!routine // ($!routine := $!profile.routines[self.routine-id])
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
    method report(MoarVM::Profile::GC:D: :$bold, :$header) {
        my &bold = $bold ?? &UNIT::bold !! &plain;
        my $*BOLD;  # don't want auto-bolding

        my $text := sprintf "%s %4s %s %8s  %s  %s  %s  %6s roots\n",
          bold(sprintf("%8s", milli(self.time))),
          self.sequence-num,
          self.full ?? bold('*') !! ' ',
          milli(self.start-time),
          bold(sprintf("%8s", bytes(self.retained-bytes))),
          bold(sprintf("%8s", bytes(self.promoted-bytes))),
          bold(sprintf("%8s", bytes(self.cleared-bytes))),
          self.gen2-roots;

        $header
          ?? "    time seq# F  started  retained  promoted     freed    gen2\n$text"
          !! $text
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

#- Routine ---------------------------------------------------------------------
# CREATE TABLE routines(
#  id INTEGER PRIMARY KEY ASC,
#  name TEXT,
#  line INT,
#  file TEXT
# );

class MoarVM::Profile::Routine {
    has int @!parts   is built(:bind);
    has     $!profile is built;
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

    # This adds the overview information from the calls table to the
    # object, so that they can be accessed quickly in selecting and
    # sorting operations
    method add-overview(MoarVM::Profile::Routine:D: @values
    --> Nil) is implementation-detail {
        @!parts.append(@values.map(*.Int))
    }

    method id(        MoarVM::Profile::Routine:D: --> int) { @!parts[0] }
    method name-index(MoarVM::Profile::Routine:D: --> int) { @!parts[1] }
    method line(      MoarVM::Profile::Routine:D: --> int) { @!parts[2] }
    method file-index(MoarVM::Profile::Routine:D: --> int) { @!parts[3] }

    # From .add-overview
    method entries(        MoarVM::Profile::Routine:D: --> int) { @!parts[ 4] }
    method inclusive-time( MoarVM::Profile::Routine:D: --> int) { @!parts[ 5] }
    method exclusive-time( MoarVM::Profile::Routine:D: --> int) { @!parts[ 6] }
    method spesh-entries(  MoarVM::Profile::Routine:D: --> int) { @!parts[ 7] }
    method jit-entries(    MoarVM::Profile::Routine:D: --> int) { @!parts[ 8] }
    method inlined-entries(MoarVM::Profile::Routine:D: --> int) { @!parts[ 9] }
    method osr(            MoarVM::Profile::Routine:D: --> int) { @!parts[10] }
    method deopt-one(      MoarVM::Profile::Routine:D: --> int) { @!parts[11] }
    method deopt-all(      MoarVM::Profile::Routine:D: --> int) { @!parts[12] }
    method site-count(     MoarVM::Profile::Routine:D: --> int) { @!parts[13] }

    method name(MoarVM::Profile::Routine:D: --> str) {
        if @!parts[1] -> $index {
            @names[$index]
        }
        else {
            '(block)'  # UNCOVERABLE
        }
    }
    method file(MoarVM::Profile::Routine:D: --> str ) { @names[@!parts[3]] }

    method file-line(MoarVM::Profile::Routine:D: --> str) {
        @names[@!parts[3]] ~ ":" ~ @!parts[2]
    }
    method name-file-line(MoarVM::Profile::Routine:D: :$bold --> str) {
        my &bold = $bold ?? &UNIT::bold !! &plain;
        (my int $index = @!parts[1])
          ?? bold(@names[$index]) ~ " " ~ self.file-line
          !! self.file-line
    }
    method io(MoarVM::Profile::Routine:D: --> IO:D) { file2io self.file  }

    method is-block(MoarVM::Profile::Routine:D: --> Bool:D) { @!parts[1] == 0 }

    method is-core(MoarVM::Profile::Routine:D: --> Bool:D) {
        (self.line < 0 || (self.file andthen .starts-with(
          'SETTING::' | 'NQP::' | 'src/Perl6' | 'src/vm/moar' | 'src/main.nqp'
        ))).Bool
    }
    method is-user(MoarVM::Profile::Routine:D: --> Bool:D) {
        !self.is-core
    }

    method execution-type(MoarVM::Profile::Routine:D: --> Str:D) {
        self.jit-entries
          ?? 'JIT'
          !! self.spesh-entries
            ?? 'spesh'
            !! 'interp'
    }

    multi method gist(MoarVM::Profile::Routine:D: --> Str:D) {
        self.report(:header)
    }

    method report(MoarVM::Profile::Routine:D: :$bold, :$header --> Str:D) {
        my $*BOLD;  # don't want auto-bolding here
        my int $total-time = $!profile.overviews.head.total-time;

        my $line1 := sprintf "%9d %s  %s  %6s  %s",
          self.entries,
          percent(self.inclusive-time / $total-time, 10),
          percent(self.exclusive-time / $total-time, 10),
          self.execution-type,
          self.name;
        my $line2 := sprintf "           %s  %s %s  %s",
          milli(self.inclusive-time, 10),
          milli(self.exclusive-time, 10),
          self.osr ?? '   OSR' !! '      ',
          self.file ~ ':' ~ self.line;

        $line1 := bold($line1) if $bold;
        my $text := "$line1\n$line2\n";
        $header
          ?? "  Entries    Inclusive    Exclusive   Exec  Name\n$text"
          !! $text
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
            $!profile.source
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
class MoarVM::Profile:ver<0.0.7>:auth<zef:lizmat> {
    has $.target;
    has $.db;
    has $!source;
    has $!overviews;
    has $!calls;
    has $!calls-overview;
    has $!allocations-overview;
    has $!deallocations;
    has $!gcs;
    has $!gc-overview;
    has $!routines;
    has $!types;
    has $!types-most-allocated;
    has $!files;
    has $!ios;
    has $!names;
    has $!user-files;
    has $!user-ios;
    has $!user-names;

    proto method new(|) {*}
    multi method new(
      DB::SQLite:D $db,
                   :keep($),
    ) {
        my $target := $db.filename.IO;
        self.bless(:$target, :$db)
    }

    multi method new(
      IO:D $target where .e && .extension eq 'db',
           :keep($),
           :type($)
    ) {
        self.bless(:$target, :db(DB::SQLite.new(:filename(~$target), |%_)))
    }

    multi method new(
      IO:D $target where .e && .extension eq 'sql',
          :$keep,
          :type($)
    ) {
        my $filename := $keep ?? ~$target.extension("db") !! "";
        my $db := DB::SQLite.new(:$filename, |%_);
        $db.execute($target.slurp);

        self.bless(:$target, :$db)
    }

    multi method new(
      IO:D $target where .e,
          :$keep,
          :$actual-target,
          :$type = 'profile'
    ) {
        my $sql := $*TMPDIR.add(nano ~ ".sql");

        my $proc     := run-code($sql, $target, :$type);
        my $filename := $keep ?? $target.extension("db") !! "";
        my $db := DB::SQLite.new(:$filename, |%_);
        $db.execute($sql.slurp);
        $sql.unlink;

        self.bless(:target($actual-target // $target), :$db)
    }
    multi method new(
      Str:D $target,
           :$keep,
           :$type = 'profile'
    ) {

        # We can't dispatch properly on IO(), so we catch anything here
        # that looks like a file that needs to be run / loaded
        if $target && !$target.contains(/\s/) {
            return self.new($_, |%_, :actual-target($target))
              if .e given $target.IO;
        }

        my str $root  = ~nano;
        my $filename := $keep
          ?? $keep ~~ Str
            ?? ~$keep.IO.add("$root.db")  # UNCOVERABLE
            !! "$root.db"
          !! "";
        my $sql      := $*TMPDIR.add("$root.sql");
        my $proc     := run-code($sql, "-e", $target, :$type);
        my $db       := DB::SQLite.new(:$filename, |%_);
        $db.execute($sql.slurp);

        $db.execute("CREATE TABLE meta(source TEXT)");
        $db.query("INSERT INTO meta (source) VALUES (?)", $target);

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

    multi method gist(MoarVM::Profile:D: --> Str:D) {
        self.report
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
#my $then := nano;
#my $result :=
        $!db.query($query, |c)
#; say nano - $then; $result
    }

    method report(MoarVM::Profile:D:
      Bool() :bold($*BOLD),
      Int:D  :$routines          = 5,
      Int:D  :$types             = 5,
      Int:D  :$routines-per-type = 3,
      Int:D  :$gcs               = 5,
    --> Str:D) {
        my &bold = $*BOLD ?? &UNIT::bold !! &plain;

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

        my @gcs := self.gcs;

        my $allocations-overview := self.allocations-overview;
        my $replaced  := $allocations-overview.replaced;
        my $allocated := $allocations-overview.allocated - $replaced;

        my str @parts;
        my sub add(str $text) { @parts.push($text) }

        my $target := $!target;
        my $now  := now;
        my $when := datetime($target ~~ IO
          ?? $target.extension eq 'db' | 'sql'
            ?? $target.created
            !! $target.changed
          !! $now
        );

        add "MoarVM Profiler Results at &datetime($now)";
        add "=" x 80;
        if $target ~~ IO {
            add $target.extension eq 'db' | 'sql'
              ?? "From &bold($target) (created $when)\n"
              !! "From &bold($target) (changed $when)\n";
        }
        add bold(self.source);

        add "";
        add "Time Spent";
        add "=" x 80;
        add "The profiled code ran for &milli($total-time).";
        add "Of this, &milli($total-gc-time) were spent in garbage collection (that's &percent($total-gc-time / $total-time))."
          if @gcs;
        add "The dynamic optimizer was active for &percent($spesh-time / $total-time) of the program's run time.";

        add "";
        add "Call Frames";
        add "=" x 80;
        add "In total, &bold("$entered-total call frames") were entered and exited by the profiled code.";
        add "Inlining eliminated the need to create &bold("$inlined-total call frames") (that's &percent($inlined-total / $calls-total))."
          if $inlined-total;
        add "&bold($interpreted-total) call frames were interpreted, &bold($spesh-total) were specialized (&percent($spesh-total / $calls-total)).";

        if @gcs {
            add "";
            add "Garbage Collection";
            add "=" x 80;
            add "The profiled code did &bold("@gcs.elems() garbage collections").";
            if @gcs.grep(*.full).elems -> $full {
                add "There were &bold("$full full collections") involving the entire heap.";  # UNCOVERABLE
            }
            add "The average nursery collection time was &milli($gc-overview.avg-minor-time).";
            add "Scalar replacement eliminated &bold($replaced) allocations (that's &percent($replaced / $allocated)).";
        }

        if $spesh-jit-total {
            add "";
            add "Dynamic Optimization";
            add "=" x 80;

            add $deopt-one-total
              ?? "Of &bold($spesh-jit-total) optimized frames, there were &bold("$deopt-one-total deoptimizations") (that's &percent($deopt-one-total / $spesh-jit-total))."
              !! "&bold($spesh-jit-total) optimized frames were seen.";
            if $deopt-all-total {
                add $deopt-all-total == 1
                  ?? "There was &bold("one global deoptimization")."
                  !! "There were &bold("$deopt-all-total global deoptimizations").";
            }
            if $osr-total {
                add $osr-total == 1
                  ?? "There was &bold("one On Stack Replacement") performed."
                  !! "There were &bold("$osr-total On Stack Replacements") performed.";
            }
        }

        if $routines -> $limit {
            my @routines := self.routines;

            add "";
            add $limit < @routines
              ?? "@routines.elems() Routines (showing $limit with most CPU usage)"
              !! "@routines.elems() Routines";
            add "=" x 80;
            @parts.append: self.routines
              .grep({ $_ &&  (.entries > 1) })
              .sort(-*.exclusive-time)
              .head($limit)
              .map(*.report(:bold($*BOLD), :header(!$++)));
        }

        if $types -> $limit {
            my @types := self.types-most-allocated;
            add $limit < @types
              ?? "@types.elems() Types (showing $limit most allocated)"
              !! "@types.elems() Types";
            add "=" x 80;
            @parts.append: @types
              .head($limit)
              .map(*.report(
                     :bold($*BOLD),
                     :header(!$++),
                     :limit($routines-per-type)
              ));
        }

        if @gcs && $gcs -> $limit {
            add $limit < @gcs
              ?? "@gcs.elems() Garbage Collections (showing $limit slowest)"
              !! "@gcs.elems() Garbage Collections";
            add "=" x 80;
            @parts.append: @gcs
              .sort(-*.time)
              .head($limit)
              .map(*.report(:bold($*BOLD), :header(!$++)));
        }

        @parts.join("\n")
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
            @routines[.head].add-overview(.skip)
              for self.query(q:to/SQL/).arrays;
SELECT
  routine_id,
  TOTAL(entries),
  TOTAL(CASE WHEN rec_depth = 0 THEN inclusive_time ELSE 0 END),
  TOTAL(exclusive_time),
  TOTAL(spesh_entries),
  TOTAL(jit_entries),
  TOTAL(inlined_entries),
  TOTAL(osr),
  TOTAL(deopt_one),
  TOTAL(deopt_all),
  COUNT(id)
FROM calls
GROUP BY routine_id
SQL
            $!routines := @routines.List
        }
    }

    method source(MoarVM::Profile:D: --> Str:D) {
        $!source // ($!source := self.query(q:to/SQL/).value
SELECT 1 FROM sqlite_master WHERE type='table' AND name='meta'
SQL
              ?? self.query("SELECT source FROM meta").value
              !! Nil
        )
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
            @types[.head].add-overview(.skip)
              for self.query(q:to/SQL/).arrays;
SELECT
  type_id,
  TOTAL(spesh),
  TOTAL(jit),
  TOTAL(count),
  TOTAL(replaced)
FROM allocations
GROUP BY type_id
SQL
            $!types := @types.List
        }
    }

    method types-most-allocated(MoarVM::Profile:D: --> List:D) {
        $!types-most-allocated // ($!types-most-allocated :=
          self.types[self.query(q:to/SQL/).arrays.flat].List
SELECT type_id FROM allocations GROUP BY type_id ORDER BY TOTAL(count) DESC
SQL
        )
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
