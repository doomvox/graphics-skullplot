#!/usr/bin/perl
# skullplot.pl                   doom@kzsu.stanford.edu
#                                27 Jul 2016

=head1 NAME

skullplot.pl - plot data from a manual db select

=head1 SYNOPSIS

  # default to first column on x-axis, all following columns on y-axis
  skullplot.pl input_data.dbox

  # specifying that explicitly
  skullplot.pl --dependents='x_axis_field' --independents='y_axis_field1,y_axis_field2' input_data.dbox

  # additional "dependents" fields determine color/shape of points
  skullplot.pl --dependents='x_axis_field1,category_field1' --independents='y_axis_field1,y_axis_field2' input_data.dbox

  # compact way of specifying similar case: first two columns independent, remaining columns dependent
  skullplot.pl --indie_count=2 input_data.dbox

  # don't use /tmp as working area
  skullplot.pl --working_loc='/var/scratch'  input_data.dbox

  # turn on debugging
  skullplot.pl -d  input_data.dbox

=head1 DESCRIPTION

B<skullplot.pl> is a script which use's the R ggplot2 library to
plot data input in the form of the output from a SELECT as
performed manually in a db shell, e.g.:

  +------------+---------------+-------------+
  | date       | type          | amount      |
  +------------+---------------+-------------+
  | 2010-09-01 | factory       |   146035.00 |
  | 2010-10-01 | factory       |   208816.00 |
  | 2011-01-01 | factory       |   191239.00 |
  | 2010-09-01 | marketing     |   467087.00 |
  | 2010-10-01 | marketing     |   409430.00 |
  +------------+---------------+-------------+

I call this "box format data" (file extension: *.dbox).

This script takes the name of the *.dbox file containing the data as an argument.
It has a number of options that control how it uses the data


The second argument is a comma-separated list of names of dependent variables
(the x-axis).
The third argument is a comma-separated list of the independent variables to
plot (the y-axis).

The default for dependent variables: the first column.
The default of independent variables: all of the following columns

The supported input data formats are as in the L<Data::BoxFormat> module.
At present, this is mysql and postgresql (including the unicode form).

=cut

use warnings;
use strict;
$|=1;
use Carp;
use Data::Dumper;

use File::Path      qw( mkpath );
use File::Basename  qw( fileparse basename dirname );
use File::Copy      qw( copy move );
use autodie         qw( :all mkpath copy move ); # system/exec along with open, close, etc
use Cwd             qw( cwd abs_path );
use Env             qw( HOME );
use List::MoreUtils qw( any );
use String::ShellQuote qw( shell_quote_best_effort );
use Config::Std;
use Getopt::Long    qw( :config no_ignore_case bundling );
use List::Util      qw( first max maxstr min minstr reduce shuffle sum );

use utf8::all;

our $VERSION = 0.01;
my  $prog    = basename($0);

my $DEBUG   = 0;
my $working_area = "$HOME/.skullplot";   # default
my ($dependent_spec, $independent_spec, $indie_count, $image_viewer);

GetOptions ("d|debug"       => \$DEBUG,
            "v|version"     => sub{ say_version(); },
            "h|?|help"      => sub{ say_usage();   },

           "indie_count=i"  => \$indie_count,      # alt spec: indies=x1+gbcats; residue are ys

           "image_viewer=s" => \$image_viewer,     # default: ImageMagick's display (if available)

           "working_area=s" => \$working_area,

           ## Experimental, alternate interface
           "dependents=s"   => \$dependent_spec,   # the x-axis, plus any gbcats
           "independents=s" => \$independent_spec, # the y-axis
           ) or say_usage();

$image_viewer ||= 'display';

mkpath( $working_area ) unless( -d $working_area );

# TODO dev only: remove when shipped.
use FindBin qw( $Bin );
use lib ("$Bin/../lib/",
         "$Bin/../../Data-BoxFormat/lib",
         "$Bin/../../Data-Classify/lib",
         "$Bin/../../Graphics-Skullplot/lib");

use Data::BoxFormat;
use Data::Classify;
use Graphics::Skullplot;

my $dbox_file = shift;

unless( $dbox_file ) {
  die "An input data file (*.dbox) is required.";
}

# TODO maybe yagni out this *_spec shit
if( $dependent_spec && not( $independent_spec ) ) {
  die "When using dependents option, also need independents.";
} elsif( $independent_spec && not( $dependent_spec ) ) {
  die "When using independents option, also need dependents.";
} elsif( $indie_count && $dependent_spec) {
  die "Use either indie_count or dependents/independents options, not both.";
}

if ( $dependent_spec ) {
  ($DEBUG) &&
    print STDERR "Using independents: $independent_spec and dependents: $dependent_spec\n";
} elsif( $indie_count )  {
  ($DEBUG) &&
    print STDERR "Given indie_count: $indie_count\n";
} else {
  ($DEBUG) &&
    print STDERR "Using default indie_count of 1\n";
  $indie_count = 1;
}

my $opt = { indie_count      => $indie_count,
            dependent_spec   => $dependent_spec,
            independent_spec => $independent_spec,
             };

my $gsp = Graphics::Skullplot->new( working_area => $working_area,
                                    image_viewer => $image_viewer);

$gsp->show_plot( $dbox_file, $opt ); # TODO rename with "exec", make clear this must be last?

#######
### end main, into the subs

sub say_usage {
  my $usage=<<"USEME";
  $prog -[options] [arguments]

  Options:
     -d          debug messages on
     --debug     same
     -h          help (show usage)
     -v          show version
     --version   show version

TODO add additional options

USEME
  print "$usage\n";
  exit;
}

sub say_version {
  print "Running $prog version: $VERSION\n";
  exit 1;
}


__END__

=head1 NOTES

I think I like the idea of doing it like this:

  One gb_cat:   use color
  Two gb_cats:  use shape for one with fewest values, use color for the other.
                   (( but if that value count exceeds ~6, fuse both as color ))
  Three gb_cats: use shape for the one with fewest values (( ditto ))
                 fuse the remaining items into a joint string value,
                 assign that to color.

((And: this logic is getting complex enough to move to a Skullplot module
of some sort, which could open the door to a seperate package again.))

  What name? No reason to *presume* R/ggplot2, that's a plug-in style choice.

=head2 SNIPPETS

  # TODO make choice of display app settable...
  #      have an intelligent default: look at what's available.

  # Running a desktop app is faster than R's browseURL:
  # system("gthumb $png_file    $erroff");
  # system("eog $png_file       $erroff");
  # system("display $png_file   $erroff");  # ImageMagick
  # exec(qq{ display  $png_file $erroff }); # ImageMagick
  # exec(qq{ display -title 'skullplot'  $png_file $erroff }); # ImageMagick


=head1 AUTHOR

Joseph Brenner, E<lt>doom@kzsu.stanford.eduE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2016 by Joseph Brenner

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=head1 BUGS

None reported... yet.

=cut
