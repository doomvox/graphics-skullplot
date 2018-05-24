package Graphics::Skullplot;
use Moo;
use MooX::Types::MooseLike::Base qw(:all);

=head1 NAME

Graphics::Skullplot - The great new Graphics::Skullplot! TODO revise this

=head1 VERSION

Version 0.01

=cut

# TODO revise these before shipping
our $VERSION = '0.01';
my $DEBUG = 1;

=head1 SYNOPSIS

   my $gsp = Graphics::Skullplot->new( working_area => $working_area,
                                       image_viewer => $image_viewer);
   my $opt = ;
   $gsp->show_plot_and_exit( $dbox_file, { indie_count      => $indie_count,
                                  dependent_spec   => $dependent_spec,
                                  independent_spec => $independent_spec,
                                 } ); 

=head1 DESCRIPTION

Graphics::Skullplot is a module that works with the result from a database 
select in the common tabular text "data box" format. It has routines that 
can be used to generate and display plots of the data in png format.

=head1 METHODS

=over

=cut

use 5.008;
use Carp;
use Data::Dumper;
use File::Basename  qw( fileparse basename dirname );
use List::Util      qw( first max maxstr min minstr reduce shuffle sum );
use List::MoreUtils qw( any zip uniq );

use Data::BoxFormat;
use Data::Classify;

# needed for accessor generation
our $AUTOLOAD;

=item new

Creates a new Graphics::Skullplot object.
Object attributes:

=over

=item working_area

Scratch location where intermediate files are created.
Defaults to "/tmp".

=item image_viewer

Defaults to 'display', the ImageMagick viewer

=back

=cut

# Example attribute:
# has is_loop => ( is => 'rw', isa => Int, default => 0 );

# required arguments to new
has input_file => ( is => 'ro', isa => Str );  # currently, must be dbox format
has plot_hints => ( is => 'ro', isa => HashRef );

# strongly recommended argument "working_area".  image_viewer has okay default.
# (( TODO I can't use the "default" value, Str complains if you give it an undef
#      Try:  Maybe[Str]  ))
has working_area => ( is => 'rw', isa => Str, default => "/tmp" );
has image_viewer => ( is => 'rw', isa => Maybe[Str], default => "display" );  # ImageMagick

# mostly internal use
has naming         => ( is => 'rw', isa => HashRef ); # lazy via generate_output_filenames?
has field_metadata => ( is => 'rw', isa => HashRef ); # need wrapper around D::C classify_fields_simple (and another wrapper inside D::C that defaults to simple for now...)


=item generate_output_filenames

Example usage: 

  # relies on "input_file" field in object, along with "working area"
  my $fn = 
    generate_filenames();
  my $basename = $fn->{ base };
  # full paths to file in $working_area
  my $tsv_file  = $fn->{ tsv };  
  my $png_file  = $fn->{ png };  

=cut 

sub generate_output_filenames {
  my $self = shift;
  my $input_file   = $self->input_file   || shift;
  my $working_area = $self->working_area || shift;
  
  my $basename = basename( $input_file ); # includes file-extension

  my ($short_base, $ext);
  if( ( $short_base = $basename ) =~ s{ \. (.*) $ }{}x ) { 
    $ext = $1;
  }

  my $tsv_name     = $short_base . '.tsv';
  my $rscript_name = $short_base . '.r';
  my $png_name     = $short_base . '.png';
  
  my $tsv_file     = "$working_area/$tsv_name";
  my $rscript_file = "$working_area/$rscript_name";
  my $png_file     = "$working_area/$png_name";

  my %filenames =
    (
     base             => $basename,
     base_sans_ext    => $short_base,
     ext              => $ext,
     tsv              => $tsv_file,
     rscript          => $rscript_file,
     png              => $png_file
     );
  $self->naming( \%filenames );
  return \%filenames;
}


=item plot_tsv_to_png

Generate the r-code to plot the tsv file data as the png file.
Takes two arguments, the hash of file definitions and 
the hash of field metadata.

   x-axis  ...  y-axis  ... 

   x-axis  gb-cat1  ... y-axis  ... 

   x-axis  gb-cat1  gb-cat2  ... y-axis  ... 

Example usages:  

  # uses "naming" and "field_metadata" from object
  $self->plot_tsv_to_png();

=cut 

sub plot_tsv_to_png {
  my $self = shift;
  my $fn = $self->naming         || shift;
  my $fd = $self->field_metadata || shift; 
#  my ($x_field, $y_field, $gb_cats) = @{ $fd->{ qw( x  y  gb_cats ) }}; # hash slice (mangled)

  my $x_field = $fd->{ x };
  my $y_field = $fd->{ y };
  my $gb_cats = $fd->{ gb_cats };

  my $tsv_file     = $fn->{ tsv };
  my $rscript_file = $fn->{ rscript };
  my $png_file     = $fn->{ png };
  
  my @gb_cats = @{ $gb_cats }; # TODO cleanup 

  # TODO
  # At present, limited to two group by categories (in addition to the x-axis)
  # Maybe: if there's more than 2, fuse them together into a compound cat, hand to colour
  my $gb_cat1 = $gb_cats[0] if $gb_cats[0];
  my $gb_cat2 = $gb_cats[1] if $gb_cats[1];

  # plot code
  my $pc = 'ggplot( skull, ' ;
  $pc .= '               aes(' ;
  $pc .= "                    x = $x_field," ;
  $pc .= "                    y = $y_field, " ;
  $pc .= "                    colour = $gb_cat1," if $gb_cat1;
  $pc .= "                    shape  = $gb_cat2 " if $gb_cat2;
  $pc .= '                          ))' ;
  $pc .= ' + geom_point( ' ;
  $pc .= "              size  = 2.5 " ;
  $pc .= '              )  ' ;

  # Generate the file of R code to run with an Rscript call
  # (in debug mode, make it a standalone unix script)
  my $r_code;
  $r_code = qq{#!/usr/bin/Rscript} . "\n" if $DEBUG;

  $r_code .=<<"__END_R_CODE";
library(ggplot2)
skull <- read.delim("$tsv_file", header=TRUE)
png("$png_file") # send plot output to png
$pc
graphics.off()   # doesn't chatter like dev.off
__END_R_CODE

  print $r_code, "\n" if $DEBUG;

  open my $out_fh, '>', $rscript_file;
  print { $out_fh } $r_code;
  close( $out_fh );

  # in case you want to run the rscript standalone
  chmod 0755, $rscript_file;

   # chdir( "$HOME/tmp" ) or die "$!";

  my $erroff = '2>/dev/null';
  $erroff = '' if $DEBUG;

  my $cmd = "Rscript $rscript_file $erroff";

  print STDERR "cmd:\n$cmd\n" if $DEBUG;
  system( $cmd );
}

=item display_png_and_exit

Open the given png file in an image viewer

This internally does an exec: it should be
the last thing called.

The image viewer can be set as the second, optional field.
The default image viewer is ImageMagick's "display".

Example usage:

  my $naming = $self->naming;
  my $png_file = $naming->{ png };
  $self->display_png_and_exit( $png_file );

=cut

sub display_png_and_exit {
  my $self = shift;
  my $png_file     = shift;  ## TODO make this optional...
  my $image_viewer = shift || 'display'; # ImageMagick viewer
# TODO do this instead soon, define default elsewhere
#  my $image_viewer = $self->image_viewer || shift;

  my $erroff = '2>/dev/null';
  $erroff = '' if $DEBUG;

  # Defaulting to ImageMagick's "display" is good, because I can
  # use a dependency on Perlmagick to ensure that it's available.
  my $vcmd;
  if ( not( $image_viewer ) or ($image_viewer eq 'display') ) {
    ### TODO improve title-- use basename, etc
    $vcmd = qq{ display -title 'skullplot'  $png_file $erroff };
  } else {
    $vcmd = qq{ $image_viewer $png_file $erroff };
  }
  exec( $vcmd );
}



=item show_plot_and_exit

The method called by the skullplot.pl script to actually
plot the data from a "data box format" file, using the 
plot_hints.

It's expected that the dbox file (L<input_file>) and the
L<plot_hints> will be defined at object creation, but at
present those settings may be overridden here and given as
first and second arguments.

This should be used at the end of the program (internally 
it does an "exec").

Example usage, over-riding object fields locally:
   
   my $plot_hints = { indie_count      => $indie_count,
                      dependent_spec   => $dependent_spec,
                      independent_spec => $independent_spec,
                    };
   $gsp->show_plot_and_exit( $dbox_file, $plot_hints ); 

=cut

sub show_plot_and_exit {
  my $self = shift;

  my $dbox_file = $self->input_file || shift;
  my $opt       = $self->plot_hints || shift;
  my $indie_count = $opt->{ indie_count };  

  my $working_area = $self->working_area;
  my $image_viewer = $self->image_viewer;

  my $naming = 
    $self->generate_output_filenames();   # now, also sets obj field 'naming'

  my $dbox_name = $naming->{ base };
  my $tsv_file  = $naming->{ tsv };

  ($DEBUG) && print "input dbox name: $dbox_name\nintermediate tsv_file: $tsv_file\n";

  # input from dbox file, output directly to a tsv file (( TODO later: move to obj field ))
  my $dbx = Data::BoxFormat->new( input_file  => $dbox_file );
  $dbx->output_to_tsv( $tsv_file );

  my @header = @{ $dbx->header() };

  # TODO: later: move to obj field (aggregation, ja?)
  my $dc = Data::Classify->new;
  my $field_metadata = 
    $dc->classify_fields_simple( $indie_count, \@header, $opt ); # TODO fixup interface
  $self->field_metadata( $field_metadata );

  $self->plot_tsv_to_png( $naming, $field_metadata ); # TODO these args are now optional

  my $png_file = $naming->{ png };
  $self->display_png_and_exit( $png_file, $image_viewer ); # TODO png_file arg still needed
}





=back

=head1 AUTHOR

Joseph Brenner, E<lt>doom@kzsu.stanford.eduE<gt>,
16 Nov 2016

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2016 by Joseph Brenner

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=head1 BUGS

Please report any bugs or feature requests to C<bug-emacs-run at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Emacs-Run>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Emacs::Run

You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Emacs-Run>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Emacs-Run>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Emacs-Run>

=item * Search CPAN

L<http://search.cpan.org/dist/Emacs-Run/>

=back

=head1 ACKNOWLEDGEMENTS


=head1 COPYRIGHT AND LICENSE

Copyright (C) 2016 by Joseph Brenner

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=cut

1;
