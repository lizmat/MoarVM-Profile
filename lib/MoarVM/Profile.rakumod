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

#- Type ------------------------------------------------------------------------
# CREATE TABLE types(
#  id INTEGER PRIMARY KEY ASC,
#  name TEXT,
#  extra_info JSON,
#  type_links JSON
# );
class MoarVM::Profile::Type {
    has @.parts is built(:bind);

    multi method new(MoarVM::Profile::Type: @a) {
        self.bless(:parts([@a[0].Int, name2index(@a[1]), @a[2], @a[3]]))
    }

    method id(  MoarVM::Profile::Type:D:) {        @!parts[0]  }
    method name(MoarVM::Profile::Type:D:) { @names[@!parts[1]] }

    method extra-info(MoarVM::Profile::Type:D:) {
        ($_ := @!parts[2]) ~~ Str ?? ($_ = from-json($_).Map) !! $_
    }
    method type-links(MoarVM::Profile::Type:D:) {
        ($_ := @!parts[3]) ~~ Str ?? ($_ = from-json($_).Map) !! $_
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
    has     $.profile;
    has int @.parts is built(:bind);

    multi method new(MoarVM::Profile::Routine: $profile, @a) {
        self.bless(:$profile, :parts(
          my int @parts =
            @a[0].Int, name2index(@a[1]), @a[2].Int, name2index(@a[3])
        ))
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

class MoarVM::Profile::Call {
    has int @.parts is built(:bind);

    multi method new(MoarVM::Profile::Call: @a) {
        self.bless(:parts(my int @parts = @a.map(*.Int)))
    }

    method id(              MoarVM::Profile::Call:D:) { @!parts[ 0] }
    method parent-id(       MoarVM::Profile::Call:D:) { @!parts[ 1] }
    method routine-id(      MoarVM::Profile::Call:D:) { @!parts[ 2] }
    method osr(             MoarVM::Profile::Call:D:) { @!parts[ 3] }
    method spesh-entries(   MoarVM::Profile::Call:D:) { @!parts[ 4] }
    method inlined-entries( MoarVM::Profile::Call:D:) { @!parts[ 5] }
    method inclusive-time(  MoarVM::Profile::Call:D:) { @!parts[ 6] }
    method exclusive-time(  MoarVM::Profile::Call:D:) { @!parts[ 7] }
    method entries(         MoarVM::Profile::Call:D:) { @!parts[ 8] }
    method deopt-one(       MoarVM::Profile::Call:D:) { @!parts[ 9] }
    method deopt-all(       MoarVM::Profile::Call:D:) { @!parts[10] }
    method rec-depth(       MoarVM::Profile::Call:D:) { @!parts[11] }
    method first-entry-time(MoarVM::Profile::Call:D:) { @!parts[12] }
    method highest-child-id(MoarVM::Profile::Call:D:) { @!parts[13] }
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

class MoarVM::Profile::RoutineOverview {
    has int @.parts is built(:bind);

    multi method new(MoarVM::Profile::RoutineOverview: @a) {
        self.bless(:parts(my int @parts = @a.map(*.Int)))
    }

    method id(             MoarVM::Profile::RoutineOverview:D:) { @!parts[ 0] }
    method entries(        MoarVM::Profile::RoutineOverview:D:) { @!parts[ 1] }
    method inclusive-time( MoarVM::Profile::RoutineOverview:D:) { @!parts[ 2] }
    method exclusive-time( MoarVM::Profile::RoutineOverview:D:) { @!parts[ 3] }
    method spesh-entries(  MoarVM::Profile::RoutineOverview:D:) { @!parts[ 4] }
    method jit-entries(    MoarVM::Profile::RoutineOverview:D:) { @!parts[ 5] }
    method inlined-entries(MoarVM::Profile::RoutineOverview:D:) { @!parts[ 6] }
    method osr(            MoarVM::Profile::RoutineOverview:D:) { @!parts[ 7] }
    method deopt-one(      MoarVM::Profile::RoutineOverview:D:) { @!parts[ 8] }
    method deopt-all(      MoarVM::Profile::RoutineOverview:D:) { @!parts[ 9] }
    method site-count(     MoarVM::Profile::RoutineOverview:D:) { @!parts[10] }

    multi method gist(MoarVM::Profile::RoutineOverview:D:) {
        my str @parts;
        for <
          id entries inclusive-time exclusive-time spesh-entries jit-entries
          jit-entries inlined-entries osr deopt-one deopt-all site-count
        > {
            if self."$_"() -> $value {
                @parts.push("$_: $value");
            }
        }
        @parts.join("\n")
    }
}

#- RoutineOverview -------------------------------------------------------------
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

class MoarVM::Profile::SpeshOverview {
    has int @.parts is built(:bind);

    multi method new(MoarVM::Profile::SpeshOverview: @a) {
        self.bless(:parts(my int @parts = @a.map(*.Int)))
    }

    method id(             MoarVM::Profile::SpeshOverview:D:) { @!parts[0] }
    method deopt-one(      MoarVM::Profile::SpeshOverview:D:) { @!parts[1] }
    method deopt-all(      MoarVM::Profile::SpeshOverview:D:) { @!parts[2] }
    method osr(            MoarVM::Profile::SpeshOverview:D:) { @!parts[3] }
    method entries(        MoarVM::Profile::SpeshOverview:D:) { @!parts[4] }
    method inlined-entries(MoarVM::Profile::SpeshOverview:D:) { @!parts[5] }
    method spesh-entries(  MoarVM::Profile::SpeshOverview:D:) { @!parts[6] }
    method jit-entries(    MoarVM::Profile::SpeshOverview:D:) { @!parts[7] }
    method sites(          MoarVM::Profile::SpeshOverview:D:) { @!parts[8] }

    multi method gist(MoarVM::Profile::SpeshOverview:D:) {
        my str @parts;
        for <
          id deopt-one deopt-all osr entries inlined-entries spesh-entries
          jit-entries sites
        > {
            if self."$_"() -> $value {
                @parts.push("$_: $value");
            }
        }
        @parts.join("\n")
    }

    multi method gist(MoarVM::Profile::SpeshOverview:D:) {
        qq:to/GIST/
id:              $.id
deopt-one:       $.deopt-one
deopt-all:       $.deopt-all
osr:             $.osr
entries:         $.entries
inlined-entries: $.inlined-entries
spesh-entries:   $.spesh-entries
jit-entries:     $.jit-entries
sites:           $.sites
GIST
    }
}

#- Profile ---------------------------------------------------------------------
class MoarVM::Profile:ver<0.0.1>:auth<zef:lizmat> {
    has $.db;
    has $!types;
    has $!routines;
    has $!routine-overviews;
    has $!spesh-overviews;

    proto method new(|) {*}
    multi method new(IO() $io where .e && .extension eq 'db') {
        self.bless(:db(DB::SQLite.new(:filename(~$io), |%_)))
    }
    multi method new(IO() $io where .e && .extension eq 'sql', :$create) {
        my $filename := $create ?? ~$io.extension("") !! "";
        my $db := DB::SQLite.new(:$filename, |%_);
        $db.execute($io,slurp);
        self.bless(:$db)
    }
    multi method new(IO() $io where !.extension, :$create) {
        given $io.extension("db") {
            return self.new($_) if .e;
        }
        given $io.extension("sql") {
            return self.new($_) if .e;
        }
        "'$io' could not be found".Failure
    }

    method types(MoarVM::Profile:D:) {
        with $!types -> @types {
            @types
        }
        else {
            my @types is default(Nil);
            for $!db.query('SELECT * FROM types').arrays -> @attributes {
                my $type := MoarVM::Profile::Type.new(@attributes);
                @types[$type.id] := $type;
            }
            $!types := @types.List
        }
    }

    method routines(MoarVM::Profile:D:) {
        with $!routines -> @routines {
            @routines
        }
        else {
            my @routines is default(Nil);
            for $!db.query('SELECT * FROM routines').arrays -> @attributes {
                my $routine := MoarVM::Profile::Routine.new(self, @attributes);
                @routines[$routine.id] := $routine;
            }
            $!routines := @routines.List
        }
    }

    method routine-overviews(MoarVM::Profile:D:) {
        with $!routine-overviews -> @overviews {
            @overviews
        }
        else {
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

    method spesh-overviews(MoarVM::Profile:D:) {
        with $!spesh-overviews -> @overviews {
            @overviews
        }
        else {
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
}

#say MoarVM::Profile::Routine.new( (0,"","",-1) );
#my $profile := MoarVM::Profile.new("foo.db");
#.say for $profile.routines.grep(*.is-user)>>.overview;
#.say for $profile.spesh-overviews;

# vim: expandtab shiftwidth=4
