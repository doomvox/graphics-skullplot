# NAME

Graphics::Skullplot - Plot the result of an SQL select (e.g. from an emacs shell window)

# VERSION

Version 0.03

# SYNOPSIS

    # To use this from emacs, see scripts/skullplot.el.
    # That elisp code accesses the perl script: scripts/skullplot.pl

    # the code used by skullplot.pl
    my $plot_hints = { indie_count           => $indie_count,
                       dependent_requested   => $dependent_requested,
                       independent_requested => $independent_requested,
                     };
    my %gsp_args = 
      ( input_file   => $dbox_file,
        plot_hints   => $plot_hints, );
    $gsp_args{ working_area } = $working_area if $working_area;
    $gsp_args{ image_viewer } = $image_viewer if $image_viewer;
    my $gsp = Graphics::Skullplot->new( %gsp_args );

    $gsp->show_plot_and_exit();  # does an exec 

# DESCRIPTION

Graphics::Skullplot is a module to graphically display the results from a database SELECT in the common tabular text "data box" format. It has routines to generate and display plots of the data in png format.

Internally it uses the [Table::BoxFormat](https://metacpan.org/pod/Table::BoxFormat) module to parse the text table,
and the [Graphics::Skullplot::ClassifyColumns](https://metacpan.org/pod/Graphics::Skullplot::ClassifyColumns) module to determine the types of the columns.

The default image viewer is the ImageMagick "display" command.

The immediate use for this code is to act as the back-end for the included 
Emacs package scripts/skullplot.el, so that database select results 
generated in an emacs shell window can be immediately plotted.  

This elisp code calls scripts/skullplot.pl, which might be used in
other contexts.

# METHODS

- new

    Creates a new Graphics::Skullplot object.
    Object attributes:

    - working\_area

        Scratch location where intermediate files are created.
        Defaults to "/tmp".

    - image\_viewer

        Defaults to 'display', the ImageMagick viewer
        (a dependency on Image::Magick ensures it's available)

- builder methods (largely for internal use)

    builder\_image\_viewer Currently just returns a hardcoded selection
    (the ImageMagick "display" program).

- generate\_output\_filenames

    Example usage: 

        # relies on object settings: "input_file" and "working area"
        my $fn = 
          generate_filenames();
        my $basename = $fn->{ base };
        # full paths to file in $working_area
        my $tsv_file  = $fn->{ tsv };  
        my $png_file  = $fn->{ png };  

- plot\_tsv\_to\_png

    Generate the r-code to plot the tsv file data as the png file.
    Takes one argument, a hash of "field metadata".  

    The file names (tsv, png, plus internal formats) come from the
    "naming" object field.

    Example usages:  

        $self->plot_tsv_to_png( $plot_cols ); 

- generate\_png\_file

    Example usage:

        $self->generate_png_file( $pc, $fn );

    Runs the given plot code (first argument) using the file-name metadata
    (second argument, defaults to object's [naming](https://metacpan.org/pod/naming)), saving the 
    plot as a png file ($fn->{png}).

    This generates a file of R code to run with an Rscript call.
    In debug mode, this generates a standalone unix script. ($DEBUG).

- display\_png\_and\_exit

    Open the given png file in an image viewer
    Defaults to "png" field in object's "naming".

    This internally does an exec: it should be
    the last thing called.

    The image viewer can be set as the second, optional field.
    The default image viewer is ImageMagick's "display".

    Example usage:

        my $naming = $self->naming;
        my $png_file = $naming->{ png };
        $self->display_png_and_exit( $png_file );

- show\_plot\_and\_exit

    The method called by the skullplot.pl script to actually
    plot the data from a "data box format" file, using the 
    plot\_hints.

    It's expected that the dbox file ([input\_file](https://metacpan.org/pod/input_file)) and the
    [plot\_hints](https://metacpan.org/pod/plot_hints) will be defined at object creation, but at
    present those settings may be overridden here and given as
    first and second arguments.

    This should be used at the end of the program (internally 
    it does an "exec").

- classify\_columns

    Given a reference to the tabular data in the form of an array of arrays,
    returns metadata for each column to be used in deciding how to plot 
    the data.

    Example usage:

        my $plot_cols = $self->classify_columns( $data );

    Classify the columns from the tabular data, returning a "fields\_metadata" hash ref.

    This is a wrapper around a provisional technique to make it easier to swap in 
    better ones later.

    At present, the metadata fields are:

         x           => $x_field  (( rename indie_x ))
         y           => $y_field
         gb_cats      => [ @gb_cats ]
         dependents_y => [ @dependents_y ]

- dumporama

    Report on state of object fields.

- fryhash

# NOTES 

## TODO

- Limited to two group by categories (in addition to the x-axis): used with colour & shape
If there's more than 2, fuse them together into a compound, use with colour
- See R Graphics Cookbook, p.205: setting up the tics and labels.

        $pc .= 'p + scale_x_date';
        $pc .= '';

- Currently this defaults to viewing images using the "display" program.
Alternately, the builder\_image\_viewer could scan through a list of 
likely viewers and pick the first that's installed.

# AUTHOR

Joseph Brenner, <doom@kzsu.stanford.edu>,
16 Nov 2016

# COPYRIGHT AND LICENSE

Copyright (C) 2016 by Joseph Brenner

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.
