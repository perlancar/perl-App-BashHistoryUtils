package App::BashHistoryUtils;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

our %SPEC;

our %arg_histfile = (
    histfile => {
        schema => 'str*',
        default => ($ENV{HISTFILE} // "$ENV{HOME}/.bash_history"),
        cmdline_aliases => {f=>{}},
        'x.completion' => ['filename'],
    },
);

our %args_filtering = (
    pattern => {
        summary => 'Match entries using a regex pattern',
        schema => 're*',
        cmdline_aliases => {p=>{}},
        tags => ['category:filtering'],
        pos => 0,
    },
    max_age => {
        summary => 'Match entries older than a certain age',
        schema => 'duration*',
        'x.perl.coerce_to' => 'int(secs)',
        tags => ['category:filtering'],
    },
    min_age => {
        summary => 'Match entries younger than a certain age',
        schema => 'duration*',
        'x.perl.coerce_to' => 'int(secs)',
        tags => ['category:filtering'],
    },
    ignore_case => {
        schema => ['bool', is=>1],
        cmdline_aliases => {i=>{}},
    },
    invert_match => {
        schema => ['bool', is=>1],
        #cmdline_aliases => {v=>{}}, # clashes with --version
    },
);

sub _do {
    require Bash::History::Read;
    require Capture::Tiny;
    require Cwd;
    #require File::Temp;

    my $which = shift;
    my %args = @_;

    my $histfile = $args{histfile};
    return [412, "Can't find '$histfile': $!"] unless -f $histfile;
    my $realhistfile = Cwd::realpath($args{histfile})
        or return [412, "Can't find realpath of '$histfile': $!"];

    if ($which eq 'grep' && !defined($args{pattern})) {
        return [400, "Missing required argument: pattern"];
    }

    my $pat;
    if (defined $args{pattern}) {
        if ($args{ignore_case}) {
            $pat = qr/$args{pattern}/i;
        } else {
            $pat = qr/$args{pattern}/;
        }
    }

    my $now = time;

    my $code;
    if ($which eq 'each') {
        $code = eval "package main; no strict; sub { $args{code} }";
        die if $@;
    } else {
        $code = sub {
            if (defined($args{max_age}) &&
                    $main::TS < $now-$args{max_age}) {
                $main::PRINT = 0;
            }
            if (defined($args{min_age}) &&
                    $main::TS > $now-$args{min_age}) {
                $main::PRINT = 0;
            }
            if ($pat && $_ =~ $pat) {
                $main::PRINT = 0;
            }

            if ($which eq 'grep') {
                $main::PRINT = !$main::PRINT;
            }
            if ($args{invert_match}) {
                $main::PRINT = !$main::PRINT;
            }
        };
    }

    local @ARGV = ($histfile);
    my $stdout = Capture::Tiny::capture_stdout(
        sub {
            Bash::History::Read::each_hist($code);
        }
    );

    if ($which eq 'grep' ||
            $which eq 'each' ||
            $which eq 'delete' && $args{-dry_run}) {
        return [200,"OK", $stdout, {'cmdline.skip_format'=>1}];
    } elsif ($which eq 'delete') {
        my $tempfile = "$realhistfile.tmp.$$";
        open my($fh), ">", $tempfile
            or return [500, "Can't open temporary file '$tempfile': $!"];

        print $fh $stdout
            or return [500, "Can't write (1) to temporary file '$tempfile': $!"];

        close $fh
            or return [500, "Can't write (2) to temporary file '$tempfile': $!"];

        rename $tempfile, $realhistfile
            or return [500, "Can't replace temporary file '$tempfile' to '$realhistfile': $!"];
    }

    [200,"OK"];
}

$SPEC{grep_bash_history_entries} = {
    v => 1.1,
    summary => 'Show matching entries from bash history file',
    args => {
        %arg_histfile,
        %args_filtering,
    },
};
sub grep_bash_history_entries {
    _do('grep', @_);
}

$SPEC{delete_bash_history_entries} = {
    v => 1.1,
    summary => 'Delete matching entries from bash history file',
    args => {
        %arg_histfile,
        %args_filtering,
    },
    features => {
        dry_run => 1,
    },
};
sub delete_bash_history_entries {
    _do('delete', @_);
}

{
    my $spec = {
        v => 1.1,
        summary => 'Run Perl code for each bash history entry',
        args => {
            %arg_histfile,
            %args_filtering,
            code => {
                summary => 'Perl code to run for each entry',
                description => <<'_',

Inside the code, you can set `$PRINT` to 0 to suppress the output of the entry.
You can modify `$_` to modify the entry. `$TS` (timestamp) is also available.

_
                schema => 'str*',
                req => 1,
                pos => 0,
            },
        },
    };
    delete $spec->{args}{pattern};
    $SPEC{each_bash_history_entry} = $spec;
}
sub each_bash_history_entry {
    _do('each', @_);
}

1;
# ABSTRACT: CLI utilities related to bash history file

=head1 DESCRIPTION

This distribution includes the following CLI utilities:

#INSERT_EXECS_LIST


=head1 SEE ALSO

L<Bash::History::Read>
