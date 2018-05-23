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
   $gsp->show_plot( $dbox_file, { indie_count      => $indie_count,
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

has working_area => ( is => 'rw', isa => Str, default => "/tmp" );
has image_viewer => ( is => 'rw', isa => Str, default => "gthumb" );  # effective default: "display"

=item generate_output_filenames

Example usage:

  $input_file = "expensoids.dbox"; # for example, any name with an extension works
  my $fn = 
    generate_filenames( $input_file, $working_area );
  my $basename = $fn->{ base };
  # paths to file in $working_area
  my $tsv_file  = $fn->{ tsv };  
  my $png_file  = $fn->{ png };  

=cut 

# DELME
#   ( my $tsv_name     = $basename ) =~ s{ \. (.*) $ }{.tsv}x;
#   ( my $rscript_name = $basename ) =~ s{ \. (.*) $ }{.r}x;
#   ( my $png_name     = $basename ) =~ s{ \. (.*) $ }{.png}x;

sub generate_output_filenames {
  my $self = shift;
  my $input_file    = shift;
  my $working_area = shift;
  
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
  return \%filenames;
}


=item plot_tsv_to_png

Generate the r-code to plot the tsv file data as the png file.
Takes two arguments, the hash of file definitions and 
the hash of field metadata.

   x-axis  ...  y-axis  ... 

   x-axis  gb-cat1  ... y-axis  ... 

   x-axis  gb-cat1  gb-cat2  ... y-axis  ... 

Example usages:  TODO OOPS: $gcp->

#  plot_tsv_to_png( $x_field, $y_field, $gb_cats, $fn );

  plot_tsv_to_png( $fn, $fd );

=cut 

sub plot_tsv_to_png {
  my $self = shift;
  my $fn = shift;
  my $fd = shift; 
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


=item exec_to_display_png

Open the given png file in an image viewer
(does an exec as a final step: this should be the last
thing called by a script).

The image viewer can be set as the second, optional field.
The default image viewer is ImageMagick's "display".

Example uses:  TODO OOPS: $gcp->

   exec_to_display_png( $png_file );

   exec_to_display_png( $png_file, $image_viewer );

=cut

sub exec_to_display_png {
  my $self = shift;
  my $png_file     = shift;
  my $image_viewer = shift; # effective default is 'display'

  my $erroff = '2>/dev/null';
  $erroff = '' if $DEBUG;

  # Defaulting to ImageMagick's "display" is good, because I can
  # use a dependency on Perlmagick to ensure that it's available.
  my $vcmd;
  if ( $image_viewer ) { 
    $vcmd = qq{ $image_viewer $png_file $erroff };
  } else {
    $vcmd = qq{ display -title 'skullplot'  $png_file $erroff };
  }
  exec( $vcmd );
}



=item show_plot

=cut

sub show_plot {
  my $self = shift;

  # BEG show_plot( $dbox_file, $opt )
  # my $opt = { indie_count      => $indie_count,
  #             dependent_spec   => $dependent_spec,
  #             independent_spec => $independent_spec,
  #              };

  my $dbox_file = shift;
  my $opt       = shift;
  my $indie_count = $opt->{ indie_count };

  my $working_area = $self->working_area;
  my $image_viewer = $self->image_viewer;

  my $filenames = 
    $self->generate_output_filenames( $dbox_file, $working_area ); # TODO fixup interface

  my $dbox_name = $filenames->{ base };
  my $tsv_file  = $filenames->{ tsv };

  ($DEBUG) && print "input dbox name: $dbox_name\nintermediate tsv_file: $tsv_file\n";

  # input from dbox file, output directly to a tsv file
  my $dbx = Data::BoxFormat->new( input_file  => $dbox_file );
  $dbx->output_to_tsv( $tsv_file );

  my @header = @{ $dbx->header() };

  my $dc = Data::Classify->new;
  my $field_metadata = 
    $dc->classify_fields_simple( $indie_count, \@header, $opt ); # TODO fixup interface

  $self->plot_tsv_to_png( $filenames, $field_metadata );

  my $png_file = $filenames->{ png };
  $self->exec_to_display_png( $png_file, $image_viewer );
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
