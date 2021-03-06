# $Id: dependencies.pl 10084 2006-07-04 22:23:29Z cjfields $
#
#!/usr/bin/perl -w

use strict;
use warnings;
use File::Find;
use Perl6::Form;
use Getopt::Long;
use Module::CoreList;
use CPANPLUS::Backend;

my $dep_header = <<HEADER;
BioPerl Dependencies

NOTE : This file was auto-generated by the helper script
maintenance/dependencies.pl. Do not edit directly!

The following packages are used by BioPerl. While not all are required for
BioPerl to operate properly, some functionality will be missing without them.
You can easily choose to install all of these during the normal installation
process. Note that the PPM version of the BioPerl packages always tries to
install all dependencies.

The DBD::mysql, DB_File and XML::Parser modules require other applications or
databases: MySQL, Berkeley DB, and expat respectively.

NB: This list of packages is not authoritative. See the 'requires',
'build_requires' and 'recommends' sections of Build.PL instead.

HEADER

#
# command line options
#

my ($verbose, $dir, $depfile, $help, $version, $skipbio) = (0, undef, "../DEPENDENCIES.NEW", undef, "5.006001", 0);
GetOptions(
        'v|verbose' => \$verbose,
        'dir:s' => \$dir,
        'depfile:s' => \$depfile,
        'p|perl:s' => \$version,
        's|skipbio' => \$skipbio,
        'h|help|?' => sub{ exec('perldoc',$0); exit(0) }
	   );

# Directories to check
my @dirs = qw(../Bio/ );

#
# run
#

my %dependencies;
my %bp_packages;
my %core = %{$Module::CoreList::version{$version}};

# pragmas and BioPerl modules not in core (not required)
my %SKIP = map {$_ => 1} qw(base
vars
warnings
strict
constant
overload
Bio::Tools::Run::Ensembl
Bio::Ext::HMM
);

if ($dir) {
    find {wanted => \&parse_core, no_chdir => 1}, $dir;
} else {
    find {wanted => \&parse_core, no_chdir => 1}, @dirs;    
}

#
# process results
#

for my $k (keys %dependencies) {
    if (exists $bp_packages{$k} || exists $core{$k}) {
        delete $dependencies{$k};
    }
}

my $b = CPANPLUS::Backend->new();

# sort by distribution into a hash, keep track of modules

my %distrib;

for my $key (sort keys %dependencies) {
    MODULE:
    for my $m ($b->module_tree($key)) {
        if (!$m) {
            warn "$key not found, skipping";
            next MODULE;
        }
        push @{$distrib{$m->package_name}}, [$m, @{$dependencies{$m->module}}]
    }
}

open (my $dfile, '>', $depfile) || die "Can't open dependency file :$!\n";

print $dfile $dep_header;

for my $d (sort keys %distrib) {
    my $min_ver = 0;
    for my $moddata (@{$distrib{$d}}) {
        my ($mod, @bp) = @$moddata;
        for my $bp (@bp) {
            $min_ver = $bp->{ver} if $bp->{ver} >  $min_ver;
        }
    }
    print $dfile
            form
    {bullet => "* "},
    " ============================================================================== ",
    "| Distribution              | Module used - Description            | Min. ver. |",
    "|---------------------------+--------------------------------------+-----------|",
    "| {<<<<<<<<<<<<<<<<<<<<<<<} | * {[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[} | {|||||||} |",
    $d,
    [
        map {
            $_->[0]->module.' - '.$_->[1]
        } map {
            [$_->[0], $_->[0]->description || 'NA']
        } @{$distrib{$d}}
    ],
    $min_ver eq 0 ? 'None' : $min_ver,
    "|==============================================================================|",
    "| Used by:                                                                     |",
    "|------------------------------------------------------------------------------|",
    "| * {[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[} |",
    [
     map {
        my $md = $_->[0]->module;
        map {join(' - ',( $_->{file}.' - '. $md ))} @{$_}[1..$#{$_}] # obfuscated ain't it!!!
     } @{$distrib{$d}}
    ],
    " ============================================================================== ";
}

close $dfile;

exit;
#
##
### end main
##
#

#
# this is where the action is
#

sub parse_core {
    my $file = $_;
    return unless $file =~ /\.PLS$/ || $file =~ /\.p[ml]$/ ;
    return unless -e $file;
    open my $F, $file || die "Could not open file $file";
    my $pod = '';
    MODULE_LOOP:
    while (my $line = <$F>) {
        # skip POD, starting comments
        next if $line =~ /^\s*\#/xms;
        if ($line =~ /^=(\w+)/) {
            $pod = $1;
        }
        if ($pod) {
            if ($pod eq 'cut') {
                $pod = '';
            } else {
                next MODULE_LOOP;
            }
        }
        # strip off end comments
        $line =~ s/\#[^\n]+//;
        if ($line =~ /^\bpackage\s+(\S+)\s*;/) {
            $bp_packages{$1}++;
        } elsif ($line =~ /(?:['"])?\b(use|require)\s+([A-Za-z0-9:_\.\(\)]+)\s*([^;'"]+)?(?:['"])?\s*;/) {
            my ($use, $mod, $ver) = ($1, $2, $3);
            if ($mod eq 'one') {
                print "$File::Find::name: $. $line";
            }
            if (exists $SKIP{$mod}) {
                next MODULE_LOOP;
            }            
            if ($ver && $ver !~ /^v?[\d\.]+$/) {
                next MODULE_LOOP;
            }
            my $nm = $File::Find::name;
            $nm =~ s{.*(Bio.*)\.pm}{$1};
            $nm =~ s{[\\\/]}{::}g;
            if (!exists $dependencies{$mod} ||
                !(grep {$_->{file} eq $nm} @{$dependencies{$mod}})) {
                push @{ $dependencies{$mod} }, {
                    ver => $ver || 0,
                    file => $nm};
                }
        }
    }
    close $F;
}

__END__

=head1 NAME

dependencies.pl - check modules and scripts for dependencies not in core

=head1 SYNOPSIS

B<dependencies.pl> [B<--dir> path ] [B<-v|--verbose>] [B<--depfile> file]
    [B<-?|-h|--help>] [B<-p|--perl> version]

=head1 DESCRIPTION

Recursively parses directory tree given (defaults to '../Bio') and checks files
for possible dependencies and versions (use/require statements).  Checks that
modules aren't part of perl core (--version, defaults to 5.006001).  Module
information is returned using CPANPLUS and data is output to a table using
Perl6::Form (yes I managed to get perl6 in here somehow).

Requires:

File::Find        - core
Getopt::Long      - core
CPANPLUS::Backend
Perl6::Form
Module::CoreList  

=head1 OPTIONS

=over 3

=item B<--dir> path

Overides the default directories to check by one directory 'path' and
all its subdirectories.

=item B<--depfile> file

The name of the output file for the dependencies table.  Default is
'../DEPENDENCIES.NEW'

=item B<-v | --verbose>

Show the progress through files during the checking.  Not used currently.

=item B<-p | --perl> version

Perl version (in long form, i.e. 5.010, 5.006001).  Used to weed out the
core modules that should be already present (ActiveState, we're staring at
you sternly).

=item B<-s | --skipbio> 

Skips BioPerl-related modules in DEPENDENCIES.

We may add something in the future to allow other forms.

=item B<-? | -h  | --help>

This help text.

=back

=head1 FEEDBACK

=head2 Mailing Lists

User feedback is an integral part of the evolution of this and other
Bioperl modules. Send your comments and suggestions preferably to
the Bioperl mailing list.  Your participation is much appreciated.

  bioperl-l@bioperl.org                  - General discussion
  http://bioperl.org/wiki/Mailing_lists  - About the mailing lists

=head2 Reporting Bugs

Report bugs to the Bioperl bug tracking system to help us keep track
of the bugs and their resolution. Bug reports can be submitted via the
web:

  http://redmine.open-bio.org/projects/bioperl/

=head1 AUTHOR - Chris Fields

Email cjfields-at-bioperl-dot-org

=cut
