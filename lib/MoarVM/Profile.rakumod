use DB::SQLite:ver<0.7+>:auth<github:CurtTilmes>:api<1>;

my str @names = "";
my %names = "" => 0;
my sub name2index(str $name) {
    %names{$name} // do {
        my int $index = %names{$name} := @names.elems;
        @names.push($name);
        $index
    }
}

#- Routine ---------------------------------------------------------------------
class MoarVM::Profile::Routine {
    has int $.id;
    has int $.name-index is built(False);
    has int $.file-index is built(False);
    has int $.line;

    multi method new(MoarVM::Profile::Routine: @a) {
        self.bless(:id(@a[0].Int), :name(@a[1]), :file(@a[2]), :line(@a[3].Int))
    }

    method TWEAK(:$name, :$file) {
        $!name-index = name2index($name);
        $!file-index = name2index($file);
    }

    method name() { $!name-index ?? @names[$!name-index] !! '(block)' }
    method file() { @names[$!file-index] }

    method is-block(MoarVM::Profile::Routine:D:) { $!name-index == 0 }

    multi method gist(MoarVM::Profile::Routine:D:) {
        "$!id: '$.name' ($.file:$!line)"
    }
}



#- Profile ---------------------------------------------------------------------
my $default-Routine := MoarVM::Profile::Routine.new( (0,"","",-1) );
class MoarVM::Profile:ver<0.0.1>:auth<zef:lizmat> {
    has $.db;
    has @!routines is default($default-Routine);

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

    method routines(MoarVM::Profile:D:) {
        if @!routines -> @routines {
            @routines
        }
        else {
            my @routines := @!routines;
            for $!db.query(q:to/QUERY/).arrays -> @attributes {
SELECT id, name, file, line FROM routines
QUERY
                my $routine := MoarVM::Profile::Routine.new(@attributes);
                @routines[$routine.id] := $routine;
            }
            @routines
        }
    }
}

say $default-Routine;
#say MoarVM::Profile::Routine.new( (0,"","",-1) );
.say for MoarVM::Profile.new("foo.db").routines;

# vim: expandtab shiftwidth=4
