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
    },
);

$SPEC{delete_entries} = {
    v => 1.1,
    summary => 'Delete entries from bash history file',
    args => {
        %arg_histfile,
        pattern => {
            summary => 'Delete entries matching a regex pattern',
            schema => 're*',
            cmdline_aliases => {p=>{}},
        },
        ignore_case => {
            schema => ['bool', is=>1],
            cmdline_aliases => {i=>{}},
        },
        max_age => {
            summary => 'Delete entries older than ',
            schema => 'duration*',
            'x.perl.coerce_to' => 'int(secs)',
        },
    },
};
sub delete_entries {
    require Bash::History::Read;
    require Capture::Tiny;
    require Cwd;
    #require File::Temp;

    my %args = @_;

    my $histfile = $args{histfile};
    return [412, "Can't find '$histfile': $!"] unless -f $histfile;
    my $realhistfile = Cwd::realpath($args{histfile})
        or return [412, "Can't find realpath of '$histfile': $!"];

    my $pat;
    if (defined $args{pattern}) {
        if ($args{ignore_case}) {
            $pat = qr/$args{pattern}/i;
        } else {
            $pat = qr/$args{pattern}/;
        }
    }

    local @ARGV = ($histfile);
    my $now = time;
    my $stdout = Capture::Tiny::capture_stdout(
        sub {
            Bash::History::Read::each_hist(
                sub {
                    if (defined($args{max_age}) &&
                            $main::TS < $now-$args{max_age}) {
                        $main::PRINT = 0;
                    }
                    if ($pat && $_ =~ $pat) {
                        $main::PRINT = 0;
                    }
                });
        });

    my $tempfile = "$realhistfile.tmp.$$";
    open my($fh), ">", $tempfile
        or return [500, "Can't open temporary file '$tempfile': $!"];

    print $fh $stdout
        or return [500, "Can't write (1) to temporary file '$tempfile': $!"];

    close $fh
        or return [500, "Can't write (2) to temporary file '$tempfile': $!"];

    rename $tempfile, $realhistfile
        or return [500, "Can't replace temporary file '$tempfile' to '$realhistfile': $!"];

    [200,"OK"];
}

1;
# ABSTRACT: CLI utilities related to bash history file

=head1 DESCRIPTION

This distribution includes the following CLI utilities:

#INSERT_EXECS_LIST


=head1 SEE ALSO

L<Bash::History::Read>
