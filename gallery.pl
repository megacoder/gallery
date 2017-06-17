#!/usr/bin/perl -w
# Copyright © 2000, 2001, 2002, 2003, 2004 Jamie Zawinski <jwz@jwz.org>
#
# Permission to use, copy, modify, distribute, and sell this software and its
# documentation for any purpose is hereby granted without fee, provided that
# the above copyright notice appear in all copies and that both that
# copyright notice and this permission notice appear in supporting
# documentation.  No representations are made about the suitability of this
# software for any purpose.  It is provided "as is" without express or 
# implied warranty.
#
# Created: 13-Sep-00.
#
# Generates an HTML gallery of images, with thumbnail pages, plus an HTML
# page for each image, with previous/next/etc links.
#
# For an example of the kinds of pages this script generates, see the
# DNA Lounge photo galleries:
#
#    http://www.dnalounge.com/gallery/
#
# Usage:  gallery.pl *.jpg
#
#    For each xyz.jpg file, it will create xyz-thumb.jpg and xyz.html, plus
#    a top-level index.html file displaying the thumbnails.  There are a
#    number of additional options:
#
#    --width N		How wide (in pixels) the thumbnail index page should
#	 		be.  The generated HTML does not auto-wrap, but has a
#	 		fixed width, with images centered on the lines.
#			Default: 680 pixels.
#
#    --lines N		How many rows of thumbnails should be generated
#			before rolling over to a second (or third) index
#			page.  Default 0, meaning put all thumbs on one
#			page.  If you set this to 10, and you have 200
#			lines of images, you'll get 20 index pages, named
#			"index.html", "index2.html" ... "index20.html", all
#			linked together.
#
#    --thumb-height N	When generating thumbnail images, how tall they
#			should be.  Note: thumbnails are only generated if
#			the thumb JPG file does not already exist, so if you
#			change your mind about the thumb height, delete all
#			the *-thumb.jpg files first to make them be
#			regenerated.
#
#    --captions		If this is specified, then each thumbnail will have
#			its file name displayed below it on the index page.
#			Off by default.
#
#    --title STRING	What to use for page titles on the index pages.
#			Default: "Page %d".  (The string '%d' is replaced
#			with the index page number.)
#
#    --verbose		Be loud; to be louder, "-vvvvv".
#
#    --re-thumbnail     In this mode, no HTML is generated; instead, it
#                       re-builds any thumbnail files that are older than
#                       their corresponding images.  In this mode (and only
#                       in this mode) the thumbs will be built with the same
#                       dimensions as before.
#
#    Additional options are the names of the image files, which can be GIF or
#    JPEG files.  Files ending with "-thumb.jpg" and ".html" are ignored, as
#    are emacs backup files, so it's safe to do "gallery.pl *" without
#    worrying about the extra stuff the wildcard will match.
#
#    Additionally, the option "--heading HTML-STRING" can appear mixed in
#    with the images: it emits a subheading at that point on the index page.
#    So, the arguments
#
#        1.jpg 2.jpg 3.jpg --heading 'More Images' 4.jpg 5.jpg 6.jpg
#
#    would put a line break and the "More Images" heading between images
#    4 and 5.  It will also place a corresponding named anchor there.
#
#    Files are never overwritten unless their contents would have changed,
#    so you can re-run this without your write dates getting lost.


require 5;
use diagnostics;
use strict;
use bytes;    # Larry can take Unicode and stick it up his ass sideways
use Config;

my $progname = $0; $progname =~ s@.*/@@g;
my $version = q{ $Revision: 1.1.1.1 $ }; $version =~ s/^[^0-9]+([0-9.]+).*$/$1/;

my @signames = split(' ', $Config{sig_name});

my $verbose = 0;

my $page_width = 680;
my $page_lines = 0;
my $thumb_height = 120;
my $captions_p = 0;
my $do_last_link_p = 1;
my $re_thumb_p = 0;

my $title = "Page %d";

my $thumb_cjpeg_args = "-opt -qual 92";

my $thumb_page_header = "<!-- %%NOWRAP%% -->\n" .
                        "<HTML>\n" .
                        " <HEAD>\n" .
                        "  <TITLE>%%TITLE%%</TITLE>\n" .
                        "  <LINK REL=\"shortcut icon\"" .
                               " HREF=\"/favicon.ico\"" .
                               " TYPE=\"image/x-icon\">\n" .
                        "%%LINKS%%" .
                        "  <STYLE TYPE=\"text/css\">\n" .
                        "   <!--\n" .
                        "    BODY { margin: 0em 1em 0em 1em; }\n" .
                        "    \@media print {\n" .
                        "     *  { color: black !important;\n" .
                        "          border-color: black !important;\n" .
                        "          background: white !important; }\n" .
                        "     .noprint { display: none !important; }\n" .
                        "    }\n" .
                        "   -->\n" .
                        "  </STYLE>\n" .
                        " </HEAD>\n" .
                        " <BODY BGCOLOR=\"#000000\" TEXT=\"#00FF00\" " .
                        "LINK=\"#00DDFF\" VLINK=\"#AADD00\"\n" .
                        "       ALINK=\"#FF6633\">\n" .
                        "  <H1 ALIGN=CENTER>%%TITLE%%</H1>\n" .
                        "\n";

my $image_page_header = $thumb_page_header;

my $thumb_page_footer = " </BODY>\n</HTML>\n";
my $image_page_footer = " </BODY>\n</HTML>\n";

my $open_table = "   <TABLE BORDER=0 CELLPADDING=0 CELLSPACING=8>\n";


sub error {
  ($_) = @_;
  print STDERR "$progname: $_\n";
  exit 1;
}

sub capitalize {
  my ($s) = @_;
  $s =~ s/_/ /g;
  # capitalize words, from the perl faq...
  $s =~ s/((^\w)|(\s\w))/\U$1/g;
  $s =~ s/([\w\']+)/\u\L$1/g;   # lowercase the rest

  # conjuctions and other small words get lowercased
  $s =~ s/\b((a)|(and)|(in)|(is)|(it)|(of)|(the)|(for)|(on)|(to))\b/\L$1/ig;

  # initial and final words always get capitalized, regardless
  $s =~ s@(^|[-/]\s*)(\w)@$1\u$2@gs;
  $s =~ s/(\s)(\S+)$/$1\u\L$2/;

  # force caps for some things (CD numbers, roman numerals)
  $s =~ s/\b((((cd)|(ep)|(lp))\d*)|([ivxcdm]{3,}))\b/\U$1/ig;

  return $s;
}


# returns an anchor string from some HTML text
#
sub make_anchor {
  my ($anchor, $count) = @_;

  $anchor =~ s@^(\s*</?(BR|P)\b[^<>]*>\s*)+@@sgi; # lose leading white tags
  $anchor =~ s@</?(BR|P)\b[^<>]*>.*$@@sgi;        # only use first line

  $anchor =~ s@</?(BR|P)\b[^<>]*>@ @gi; # tags that become whitespace
  $anchor =~ s/<[^<>]*>//g;             # lose all other tags
  $anchor =~ s/\'s/s/gi;		# posessives
  $anchor =~ s/\.//gi;			# lose dots
  $anchor =~ s/[^a-z\d]/ /gi;           # non alnum -> space
  $anchor =~ s/^ +//;                   # trim leading/trailing space
  $anchor =~ s/ +$//;
  $anchor =~ s/\s+/_/g;                 # convert space to underscore
  $anchor =~ tr/A-Z/a-z/;               # downcase

  $anchor =~ s/^((_?[^_]+){5}).*$/$1/;  # no more than 5 words

  if ($anchor eq '' && $count > 0) {
    # kludge for when we had some headings, but then go back to "no heading"
    # at the end of the gallery...
    $anchor = 'bottom';
  }

  return $anchor;
}


# Generates a bunch of HTML pages for a gallery of the given image files.
# These are the indexN pages that contain inline thumbnails.
#
sub generate_pages {
  my (@images) = @_;

  my %thumbs  = ();
  my %widths  = ();
  my %heights = ();

  # For each image: ensure there is a thumbnail, and find the sizes of both.
  #
  foreach my $img (@images) {

    next if ($img =~ m/^--heading /);

    if ($img =~ m/\.gif$/i) {
      $_ = `giftopnm '$img' 2>/dev/null | head -2`;
    } else {
      $_ = `djpeg '$img' 2>/dev/null | head -2`;
    }
    my ($w, $h) = m/^(\d+) (\d+)$/m;

    if (! $h) {
      print STDERR "$progname: not a GIF or JPEG file: $img\n";
      next;
    }

    $widths{$img} = $w;
    $widths{$img} = $h;

    my $t;
    ($t, $w, $h) = thumb ($img, $w, $h);

    $thumbs{$img} = $t;
    $widths{$t} = $w;
    $heights{$t} = $h;
  }

  return if ($re_thumb_p);

  my @pages = ();
  my @page = ();
  my @line = ();
  my $x = 0;
  my $y = 0;
  foreach my $img (@images) {

    my $heading_p = ($img =~ m/^--heading /);

    my $thumb = $thumbs{$img};
    next unless ($heading_p || defined($thumb)); # warning was already printed

    my $w = ($heading_p ? -1 : $widths{$thumb});
    my $h = ($heading_p ? -1 : $heights{$thumb});

    if ($heading_p ||
        $x + $w > $page_width) {
      my @line_copy = ( @line );
      push @page, \@line_copy;
      @line = ();

      $x = 0;
      $y++;

      if ($page_lines != 0 && $y >= $page_lines) {
        my @page_copy = ( @page );
        push @pages, \@page_copy;
        @page = ();
        $y = 0;
      }
    }

    $x += $w;

    my @twh = ($heading_p
               ? ($img)
               : ($thumb, $img, $w, $h));
    push @line, \@twh;
  }

  # close off last line/page.
  push @page,  \@line  if ($#line >= 0);
  push @pages, \@page  if ($#page >= 0);


  # Generate the index pages.
  #
  my $prev_file = undef;
  my $page_i = 0;

  my $first_file = $#pages == 0 ? undef : "./";
  my $last_file  = $#pages == 0 ? undef : "index" . ($#pages+1) . ".html";

  my $toplevel_title = '';

  for my $page (@pages) {
    my $page_number = $page_i + 1;
    my $line_i = 0;

    my $ptitle = $title;
    $ptitle =~ s/%d/$page_number/g;

    $_ = $thumb_page_header;
    s/%%TITLE%%/$ptitle/g;
    my $output = $_;

    my $file = ($page_i == 0 ? "./" : "index$page_number.html");
    my $next_file = ($page_i == $#pages ? undef
                     : "index" . ($page_number+1) . ".html");

    my $nav = "  <TABLE CLASS=\"noprint\" BORDER=0 WIDTH=\"100%\">\n   <TR>\n";
    my $links = '';
    $nav .= "    <TD NOWRAP ALIGN=LEFT WIDTH=\"33%\">";
    if ($prev_file) {
      $nav .= "<A HREF=\"$prev_file\"><B>&lt;&lt; prev</B></A>";
      $links .= "  <LINK REL=\"prev\"  HREF=\"$prev_file\">\n";
      $links .= "  <LINK REL=\"first\" HREF=\"$first_file\">\n";
    }
    $nav .= "</TD>\n    <TD NOWRAP ALIGN=CENTER WIDTH=\"34%\">";
    if ($page_i != 0) {
      $nav .= "<A HREF=\"./\"><B>top</B></A>"
    }
    $nav .= "</TD>\n    <TD NOWRAP ALIGN=RIGHT WIDTH=\"33%\">";
    if ($next_file) {
      $nav .= "<A HREF=\"$next_file\"><B>next &gt;&gt;</B></A>";
      $links .= "  <LINK REL=\"next\"  HREF=\"$next_file\">\n";
      $links .= "  <LINK REL=\"last\"  HREF=\"$last_file\">\n"
        if ($do_last_link_p);
    }

    $nav .= "</TD>\n   </TR>\n  </TABLE>\n";

    $nav = "\n" unless ($prev_file || $next_file);  # only one page

    $output .= $nav;
    $output =~ s/%%LINKS%%/$links/g;

    $output .= "  <DIV ALIGN=CENTER>\n";
    $output .= "   <NOBR>" unless ($captions_p);

    my $heading_count = 0;

    for my $line (@{$page}) {

      if ($captions_p) {
        $output .= $open_table;
        $output .= "    <TR>";
      }

      for my $twh (@{$line}) {
        my ($thumb, $img, $w, $h) = @{$twh};

        my $heading_p = ($thumb =~ m/^--heading (.*)/);

        if ($heading_p) {
          my $heading = $1;
          my $anchor = make_anchor ($heading, $heading_count);

          $heading = '<P>' if ($heading eq '');

          print STDERR "$progname: anchor: $anchor\n" if ($verbose > 2);
          $output .= "\n" .
                     "<P ALIGN=CENTER><A NAME=\"$anchor\"><B>" .
                     $heading .
                     "</B></A><P>\n"
            unless ($anchor eq '');
          $heading_count++ unless ($anchor eq '');
          next;
        }

        $output .= "\n ";

        my $img_html = $img;
        $img_html =~ s/\.[^.]+$/.html/;

        if ($captions_p) {
          $output .= " <TD ALIGN=CENTER VALIGN=TOP>";
        }

        $output .= "<A HREF=\"$img_html\">" .
          "<IMG SRC=\"$thumb\" WIDTH=$w HEIGHT=$h VSPACE=2 BORDER=2>" .
          "</A>";

        if ($captions_p) {
          $output .= "<BR>$img";
          $output .= "</TD>";
        }
      }

      if ($captions_p) {
        $output .= "\n    </TR>\n";
        $output .= "   </TABLE>\n";
      } else {
        $output .= "\n    <BR>";
      }

      $line_i++;
    }

    $output .= "\n   </NOBR>\n" unless ($captions_p);
    $output .= "  </DIV>\n\n";

    # remove blank line before first subheading
    $output =~ s@(<NOBR>)(\s*<BR>)@$1@i;

    if ($nav =~ m/^\s*$/s) {
      $nav = "  <P CLASS=\"noprint\" ALIGN=CENTER>\n" .
             "   <FONT SIZE=\"+1\">" .
                 "<A HREF=\"../\">&lt;&lt; up</A></FONT>\n" .
             "  <P>\n";
    }

    $output .= $nav;
    $output .= $thumb_page_footer;

    my $file2 = $file;
    $file = "index.html" if ($file eq "./");

    $output = splice_existing_header ($output, $file);

    # Give the image pages the same title as the top-level page.
    #
    if ($toplevel_title eq '') {
      $output =~ m@<TITLE\b[^<>]*>(.*?)</TITLE\b[^<>]*>@ ||
        error ("$file: no <TITLE>");
      $toplevel_title = $1;
      $toplevel_title =~ s@\s*\bPage\s*\d+@@gsi;

      print STDERR "$progname: WARNING: no useful title in index.html: " .
                   "please use --title\n"
        if ($toplevel_title eq '');
    }

    local *OUT;
    my $file_tmp = "$file.tmp";
    open (OUT, ">$file_tmp") || error "$file_tmp: $!";
    print OUT $output || error "$file_tmp: $!";
    close OUT;

    my @cmd = ("cmp", "-s", "$file_tmp", "$file");
    print STDERR "$progname: executing \"" .
      join(" ", @cmd) . "\"\n" if ($verbose > 1);
    if (system (@cmd)) {
      if (!rename ("$file_tmp", "$file")) {
        unlink "$file_tmp";
        error "mv $file_tmp $file: $!";
      }

      print STDERR "$progname: wrote $file\n";

    } else {
      unlink "$file_tmp" || error "rm $file_tmp: $!\n";
      print STDERR "$progname: $file unchanged\n" if ($verbose);
      print STDERR "$progname: rm $file_tmp\n" if ($verbose > 2);
    }

    $prev_file = $file2;
    $page_i++;
  }


  # Generate the image pages.
  #
  my @all_images = ();
  $page_i = 0;
  for my $page (@pages) {
    my $page_number = $page_i + 1;
    my $index = ($page_i == 0 ? "./" : "index$page_number.html");

    my $last_anchor = undef;
    my $last_anchor_title = undef;

    my $heading_count = 0;
    for my $line (@{$page}) {
      for my $twh (@{$line}) {
        my ($thumb, $img, $w, $h) = @{$twh};
        if ($thumb =~ m/^--heading (.*)/) {
          $last_anchor_title = $1;
          $last_anchor = make_anchor ($last_anchor_title, $heading_count);
          $heading_count++ unless ($last_anchor eq '');
          next;
        }
        my $ii = ($last_anchor
                  ? "$index\#$last_anchor"
                  : $index);
        my @crud = ( $img, $ii, $last_anchor_title );
        my @crud_copy = ( @crud );
        push @all_images, \@crud_copy;
      }
    }
    $page_i++;
  }

  my $first = (@{$all_images[0]})[0];
  my $last  = (@{$all_images[$#all_images]})[0];

  for (my $i = 0; $i <= $#all_images; $i++) {
    my $crud0 = ($i == 0 ? undef : $all_images[$i-1]);
    my $crud1 = $all_images[$i];
    my $crud2 = $all_images[$i+1];
    my $prev = (defined($crud0) ? @{$crud0}[0] : undef);
    my $next = (defined($crud2) ? @{$crud2}[0] : undef);
    my $img  = @{$crud1}[0];
    my $index = @{$crud1}[1];
    my $ptitle = @{$crud1}[2];

    if (!$ptitle) {
      $ptitle = $toplevel_title;
    } else {
      my $tt = $toplevel_title;
      my $pt = $ptitle;
      $tt =~ s@:[^:]*$@@;
      $pt =~ s@<(P|BR)\b[^<>]*>@ / @gi;
      $pt =~ s@<[^<>]*>@ @gi;
      $pt = capitalize($pt);
      $ptitle = "$tt: $pt";
    }

    my $file = $img;
    $file =~ s/\.[^.]+$/.html/;
    generate_page ($img, $ptitle, $index, $prev, $next, $first, $last);
    $page_i++;
  }
}


# Generates an HTML page for wrapping the single given image.
#
sub generate_page {
  my ($img, $title, $index_page,
      $prev_img, $next_img, $first_img, $last_img) = @_;

  $_ = $image_page_header;

#  if (!$captions_p) {
    s@<H1[^<>]*>[^<>]*</H1[^<>]*>\s*@@gi;  # delete <H1>
#  }

  $title .= ": $img";
  $title =~ s@\.[^.\s/]+$@@;
  s/%%TITLE%%/$title/g;
  my $output = $_;

  if ($img =~ m/\.gif$/i) {
    $_ = `giftopnm '$img' 2>/dev/null | head -2`;
  } else {
    $_ = `djpeg '$img' 2>/dev/null | head -2`;
  }
  my ($img_width, $img_height) = m/^(\d+) (\d+)$/m;

  if (! $img_height) {
    print STDERR "$progname: not a GIF or JPEG file: $img\n";
    return undef;
  }

  my $links = '';
  my $nav = "<TABLE CLASS=\"noprint\" BORDER=0 " .
                   "CELLPADDING=4 CELLSPACING=0 WIDTH=\"100%\"><TR>";
  $nav .= "<TD NOWRAP ALIGN=LEFT WIDTH=\"33%\">";

  $links .= "  <LINK REL=\"top\"   HREF=\"../../../\">\n";
  $links .= "  <LINK REL=\"up\"    HREF=\"$index_page\">\n";

  my $first_file = $first_img;
  my $last_file  = $last_img;
  $first_file =~ s/\.[^.]+$/.html/;
  $last_file  =~ s/\.[^.]+$/.html/;

  if ($prev_img) {
    $_ = $prev_img;
    s/\.[^.]+$/.html/;
    $nav .= "<A HREF=\"$_\"><B>&lt;&lt; prev</B></A>";
    $links .= "  <LINK REL=\"first\" HREF=\"$first_file\">\n";
    $links .= "  <LINK REL=\"prev\"  HREF=\"$_\">\n";
  }
  $nav .= "</TD><TD NOWRAP ALIGN=CENTER WIDTH=\"34%\">";
  $nav .= "<A HREF=\"$index_page\">";
  $nav .= "<B>index</B></A>";
  $nav .= "</TD><TD NOWRAP ALIGN=RIGHT WIDTH=\"33%\">";
  if ($next_img) {
    $_ = $next_img;
    s/\.[^.]+$/.html/;
    $nav .= "<A HREF=\"$_\"><B>next &gt;&gt;</B></A>";
    $links .= "  <LINK REL=\"next\"  HREF=\"$_\">\n";
    $links .= "  <LINK REL=\"last\"  HREF=\"$last_file\">\n"
      if ($do_last_link_p);
  }
  $nav .= "</TD></TR></TABLE>\n";

  $output .= $nav;
  $output .= "  <DIV ALIGN=CENTER>";
  $output .= "<IMG SRC=\"$img\" WIDTH=$img_width HEIGHT=$img_height " .
             "BORDER=1>";
  $output .= "</DIV>\n  ";
  $output .= $nav;
  $output =~ s/%%LINKS%%/$links/g;

  $output .= $image_page_footer;

  my $img_html = $img;
  $img_html =~ s/\.[^.]+$/.html/;

  local *OUT;
  my $file = $img_html;
  my $file_tmp = "$file.tmp";
  open (OUT, ">$file_tmp") || error "$file_tmp: $!";
  print OUT $output || error "$file_tmp: $!";
  close OUT;

  my @cmd = ("cmp", "-s", "$file_tmp", "$file");
  print STDERR "$progname: executing \"" .
    join(" ", @cmd) . "\"\n" if ($verbose > 1);
  if (system (@cmd)) {
    if (!rename ("$file_tmp", "$file")) {
      unlink "$file_tmp";
      error "mv $file_tmp $file: $!";
    }

    print STDERR "$progname: wrote $file for " .
      "$img (${img_width}x${img_height})\n";

  } else {
    unlink "$file_tmp" || error "rm $file_tmp: $!\n";
    print STDERR "$progname: $file unchanged\n" if ($verbose);
    print STDERR "$progname: rm $file_tmp\n" if ($verbose > 1);
  }

  return ($img_html, $img_width, $img_height);
}


# Create a thumbnail jpeg for the given image, unless it already exists.
#
sub thumb {
  my ($img, $img_width, $img_height) = @_;

  my $thumb_file = $img;
  $thumb_file =~ s/(\.[^.]+)$/-thumb.jpg/;
  die if ($thumb_file eq $img);

  my $this_height = $thumb_height;
  my $this_width = int (($thumb_height * $img_width / $img_height) + 0.5);

  my $generate_p = 0;

  if (! -s $thumb_file) {
    $generate_p = 1;
  } else {
    print STDERR "$progname: $thumb_file already exists\n" if ($verbose > 1);

    if ($thumb_file =~ m/\.gif$/i) {
      $_ = `giftopnm '$thumb_file' 2>/dev/null | head -2`;
    } else {
      $_ = `djpeg '$thumb_file' 2>/dev/null | head -2`;
    }
    ($this_width, $this_height) = m/^(\d+) (\d+)$/m;

    if (! $this_height) {
      print STDERR "$progname: not a GIF or JPEG file: $thumb_file\n";
      return undef;
    }

    if ($re_thumb_p) {

      my $id = (stat($img))[9];
      my $td = (stat($thumb_file))[9];

      if ($id <= $td) {
        print STDERR "$progname: $thumb_file ($this_width x $this_height)" .
                     " is up to date\n"
          if ($verbose > 1);
      } else {
        print STDERR "$progname: $thumb_file was $this_width x $this_height\n"
          if ($verbose > 1);

        my $ir = $img_width / $img_height;
        my $tr = $this_width / $this_height;
        my $d = $ir - $tr;
        if ($d > 0.01 || $d < -0.01) {
          print STDERR "$progname: $thumb_file: ratios differ!" .
            "  $img_width x $img_height vs $this_width x $this_height\n";
        } else {
          $generate_p = 1;
        }
      }
    }
  }

  if ($generate_p) {
    my $decoder = (($img =~ m/\.gif$/i) ? "giftopnm" : "djpeg");
    my $cmd = "$decoder < '$img' | (pnmscale -height $thumb_height 2>&-) | " .
      "cjpeg $thumb_cjpeg_args > '$thumb_file'";

    print "$progname: $cmd\n" if ($verbose > 1);
    if (system ($cmd) != 0) {
      my $status = $? >> 8;
      my $signal = $? & 127;
      my $core   = $? & 128;
      $cmd =~ s/^([^\s]+).*$/$1/;
      if ($core) {
        print STDERR "$progname: $cmd dumped core\n";
      } elsif ($signal) {
        $signal = "SIG" . $signames[$signal];
        print STDERR "$progname: $cmd died with signal $signal\n";
      } else {
        print STDERR "$progname: $cmd exited with status $status\n";
      }
      exit ($status == 0 ? -1 : $status);
    }

    print STDERR "$progname: wrote $thumb_file for $img " .
      "(${img_width}x${img_height} => ${this_width}x${this_height})\n";
  }

  return ($thumb_file, $this_width, $this_height);
}


# if the given file exists, extract the HTML header from it, and return
# new HTML with that header.  This is so we can re-run this script on a
# directory after the HTML at the top of the file has been edited without
# overwriting that (but changing the thumbnail HTML.)  Kludge!
#
sub splice_existing_header {
  my ($html, $file) = @_;
  local *IN;
  if (open (IN, "<$file")) {
    my $old = '';
    while (<IN>) { $old .= $_; }
    close IN;

    my $re = '^(.*?\s*)(<DIV\s+ALIGN=CENTER>\s*<(NOBR|TABLE\b[^<>]*)>)';
    if ($old =~ m/$re/sio) {
      my $old_header = $1;
      if ($html =~
          s/$re/$old_header$2/sio) {
        print "$progname: $file: kept pre-existing header\n" if ($verbose > 1);
      } else {
        error "$file: couldn't splice pre-existing header";
      }
    }
  }

  return $html;
}


sub usage {
  print STDERR "usage: $progname [--verbose] [--width pixels] [--lines N]\n" .
             "       [--thumb-height pixels] [--re-thumbnail] [--captions]\n" .
             "       [--title string] [--heading string] image-files ...\n";
  exit 1;
}

sub main {

  my @images;
  my $tc = 0;

  while ($_ = $ARGV[0]) {
    shift @ARGV;
    if ($_ eq "--verbose") { $verbose++; }
    elsif (m/^-v+$/) { $verbose += length($_)-1; }
    elsif ($_ eq "--width") { $page_width = shift @ARGV; }
    elsif ($_ eq "--lines") { $page_lines = shift @ARGV; }
    elsif ($_ eq "--thumb-height") { $thumb_height = shift @ARGV; }
    elsif ($_ eq "--re-thumb" || $_ eq "--re-thumbnail") { $re_thumb_p = 1; }
    elsif ($_ eq "--captions") { $captions_p = 1; }
    elsif ($_ eq "--no-last") { $do_last_link_p = 0; }
    elsif ($_ eq "--title") { $title = shift @ARGV;
      error ("multiple titles: did you mean --heading?") if ($tc++ > 0); }
    elsif ($_ eq "--heading") { push @images, "$_ " . shift @ARGV; }
    elsif (m/^-./) { usage; }
    else { push @images, $_; }
  }
  usage if ($#images < 0);

  my @pruned = ();
  foreach (@images) {
    next if (m/-thumb\.jpg$/);
    next if (m/\.html$/);
    next if (m/[~%\#]$/);
    next if (m/\bCVS$/);
    push @pruned, $_;
  }

  error ("no images specified?") if ($#pruned < 0);

  generate_pages (@pruned);
}

main;
exit 0;
