package R::Comment2DocDraft;

use strict;
use English;
use File::Temp qw(tempfile);

our $VERSION = 0.1;
our %global = ("author" => "Someone <name\@site.com>",);

our %necessary_fields = ("title"     => 1,
                            );

our %fields_type = ("title"       => \&parse_paragraph,
                    "details"     => \&parse_paragraph,
                    "description" => \&parse_paragraph,
                    "arguments"   => \&parse_list,
                    "value"       => \&parse_paragraph,
                    "valuelist"   => \&parse_list,
                    "seealso"     => \&parse_vector,
                    "source"      => \&parse_paragraph,
                    "author"      => \&parse_paragraph,
                    "references"  => \&parse_paragraph,
                    "name"        => \&parse_paragraph,
                    "docType"     => \&parse_paragraph,
                    );

our %synonyms = ("desc"       => "description",
                 "parameters" => "arguments",
                 "param"      => "arguments",
                 "args"       => "arguments",
                 "arg"        => "arguments",
                 "return"     => "value",
                 "values"     => "value",
                 "reference"  => "references",
                 "detail"     => "details",
                   );

our @available_section = qw(name        alias   docType   title 
                            description usage   arguments details   
                            note        value   source    reference 
                            author      seealso example);

sub draft {
    my $class = shift;
    my $dir = shift;
    %global = (%global, @_);
    
    my ($R_MERGE_FH, $r_merge_filename) = tempfile();
    
    # find all the R script
    my @r_files;
    if( -f $dir) {
        @r_files = ($dir);
    } 
    elsif(-d $dir) {
        @r_files = glob("$dir/*.R");
    } 
    else {
        die "cannot find $dir.\n";
    }
    
    # merge all the R script into one file
    foreach my $r_file (@r_files) {
        print "- merge $r_file\n";
        
        open my $R_FH, "<", $r_file or die "cannot open $r_file.";
        print $R_MERGE_FH join "", <$R_FH>;
        print $R_MERGE_FH "\n\n";
        close $R_FH; 
    }
    
    close $R_MERGE_FH;
    
    print "R scripts are merged into $r_merge_filename\n";
    print "Convert the comment\n";
    my $data = parse($r_merge_filename);
    
    print "remove temp files ($r_merge_filename)\n";
    unlink($r_merge_filename);
    
    generate($data);
    
    print "done, you doc drafts are in /man dir.\n";
}

sub generate {
    my $draft = shift;
    
    (-d "man") or mkdir("man");


    for(my $i = 0; $i < scalar(@$draft); $i ++) {
        my $current = $draft->[$i];
        my $function_name = $current->{function_name};
        $function_name ||= $current->{name};
        if(-e "man/$function_name.rd") {
            print "- man/$function_name.rd already exists, update\n";
            my $old = read_section("man/$function_name.rd");
            update_doc($current, $old);
        } 
        else {
        
            print "- generate man/$function_name.rd\n";
            create_doc($current);
       }
        
    }
}

sub create_doc {
    my $current = shift;
    
    my $function_name = $current->{function_name};
        $function_name ||= $current->{name};
    open MAN, ">", "man/$function_name.rd" or die $!;
       
       foreach my $section (@available_section) {
        if(defined($current->{$section})) {
            if($section eq "arguments") {
                print MAN "\\arguments{\n";
                   for(my $j = 0; $j < scalar(@{$current->{arguments}->{item_name}}); $j ++) {
                    print MAN "  \\item{$current->{arguments}->{item_name}->[$j]}\n";
                    print MAN format_text("{$current->{arguments}->{item_desc}->[$j]}", "    ");
                    print MAN "\n";
                   }
                   print MAN "}\n";
            } 
            elsif($section eq "usage") {
                print MAN "\\usage{\n  $current->{function_name}($current->{function_args})\n}\n";
            } 
            elsif($section eq "seealso") {
                print MAN "\\seealso{\n";
                print MAN format_text((join ", ", @{$current->{seealso}}), "  ");
                print MAN "\n}\n";
            } 
            else {
                print MAN "\\$section\{\n"; print MAN format_text($current->{$section}, "  "); print MAN "\n}\n";
            }
        }
       }
       print MAN "\\example{\n";
       print MAN "# your example code here\n";
       print MAN "}\n";
       close MAN;
}

sub read_section {
    return {};
}

sub update_doc {
    create_doc(@_);
}

sub format_text {
    my $text = shift;
    my $prefix_space = shift;
    
    my @p = split "\n\n", $text;
    my $new_text = "";
    for(my $i = 0; $i < scalar(@p); $i ++) {
        $new_text .= format_p($p[$i], $prefix_space);
        if($i != $#p) {
            $new_text .= "\n\n";
        }
    }
    return $new_text;
}

sub format_p {
    my $text = shift;
    my $prefix_space = shift;
    
    my $max_width = 80;
    
    my @words = split /\s+/, $text;
    my $new_text = " " x (length($prefix_space) - 1);
    my $current_width = length($prefix_space) - 1;
    foreach my $word (@words) {
        if($current_width + length($word) + 1 > $max_width - 5) {
            $new_text .= "\n$prefix_space$word";
            $current_width = length($prefix_space) + length($word) + 1;
        } else {
            $new_text .= " $word";
            $current_width += length($word) + 1;
        }
    }
    
    return $new_text;

}

# get function names
# parse comment and store as perl object.
sub parse {
    
    # each element in @$draft is data containing doc and function
    my $draft = [];

    open my $R_FH, $_[0] or die "cannot open temperary file.\n";

    while(my $line = <$R_FH>) {
        
        # if the function has a doc, the comment must start with title
        
        if($line =~/^#title:/i or $line =~/^# {2, }title:/i) {
            warn "Title section should formatted as '# title:'\n";
        }
        if($line =~/^# title:/) {
            $line =~s/^# //;
            my $current_comment = $line;
            while($line = <$R_FH>) {
                
                # comment should be in one block
                unless($line =~/^#/) {
                    last;
                    }
                $line =~s/^# //;
                $line =~s/^#//;
                $current_comment .= $line;
               }
            
            # convert code to \link{} or \code{}
            $current_comment = trans_code($current_comment);
            # add \url to link
            $current_comment = trans_url($current_comment);
            
            my $current = parse_comment($current_comment);
            # skip empty lines
            $line = <$R_FH> if($line =~/^\s+$/);

            # like:
            # f = function (xxx
            my $function_name;
            my $function_args;
            unless($current->{name} and $current->{docType}){
                if($line =~/([\w.]+)\s*(=|<-)\s*function\s*\(/) {
                    # then find the closing )
                    $function_name = $1;
                   
                    my $raw_args_str = $POSTMATCH;
                    my $left_parenthese_flag = 1; # there are one unmatched left parenthese
                    my $closing_position;
                    if(($closing_position = find_closing_parenthese($raw_args_str, \$left_parenthese_flag)) > -1) {
                        $function_args = substr($raw_args_str, 0, $closing_position);
                    } else {
                        $function_args = $raw_args_str;
                        while($line = <$R_FH>) {
                            chomp $line;
                            $line =~s/^\s+//;
                            if(($closing_position = find_closing_parenthese($line, \$left_parenthese_flag)) > -1) {
                                $function_args .= substr($line, 0, $closing_position);
                                last;
                            }
                            $function_args .= $line;
                        }
                    }
                    $function_args = $function_args;

                    

                }
                else {
                    die "function args should be formatted as ($line):\n"
                          ."  f = function (x, y) or \n"
                          ."  f <- function (x, y)\n";
                }
            }
            # parse the current doc
            push(@$draft, $current);
            $draft->[$#$draft]->{function_name} = $function_name;
            $draft->[$#$draft]->{function_args} = $function_args;
            if(defined($draft->[$#$draft]->{function_name})) {
				($draft->[$#$draft]->{usage} = "$function_name($function_args)");
			}
             foreach (keys %global) {
                $draft->[$#$draft]->{$_} = $global{$_};
             }
        }
    }
    return $draft;
}

# if find the closing parenthese, return the position in the string
# else return -1
sub find_closing_parenthese {
    my $str = shift;
    my $left_parenthese_flag = shift;
    my @args_char = split "", $str;

    for(my $i = 0; $i < scalar(@args_char); $i ++) {
        if($args_char[$i] eq "(") {
            $$left_parenthese_flag ++;
        }
        elsif($args_char[$i] eq ")") {
            $$left_parenthese_flag --;
        }

        if($$left_parenthese_flag == 0) {
            return $i;
        }
    }
    return -1;
}

sub parse_comment {
    my $text = shift;
    my $function_name = shift;
    
    my @lines = split "\n", $text;

    my $res = {};
    for(my $i = 0; $i < scalar(@lines); $i ++) {
        if($lines[$i] =~/^(\w+):/) {
            my $section = $1;
            my $content;
            
            if(defined($fields_type{$section})) {
                $content = $fields_type{$section}->(\$i, @lines);
                $res->{$section} = $content;
            } elsif(defined($synonyms{$section})) {
                $content = $fields_type{$synonyms{$section}}->(\$i, @lines);
                $res->{$synonyms{$section}} = $content;
            } else {
                warn "find section:$section, but ignored.\n";
            }
        }
    }
    
    
    foreach (keys %necessary_fields) {
        if(!defined($res->{$_})) {
            die "$_ is a necessary section, but cannot find it ($function_name).";
        }
    }
    return $res;
}

sub parse_paragraph {
    my $pi = shift;
    my @lines = @_;
    my $i = $$pi;

    my $res;
    for($i ++ ; $i < scalar(@lines); $i ++) {
        if($lines[$i] =~/^\w+:/) {
            last;
        }
        $lines[$i] =~s/^\s+|\s+$//g;
        if($lines[$i] eq "") {
            $res .= "\n\n";
        } else {
            $res .= "$lines[$i] ";
        }
    }
    $res =~s/\s+$//;;

    $$pi = $i - 1;
    return $res;
}

sub parse_list {
    my $pi = shift;
    my @lines = @_;
    my $i = $$pi;

    my @item_name = ();
    my @item_desc = ();
    for($i ++ ; $i < scalar(@lines); $i ++) {
        if($lines[$i] =~/^\S+:/) {
            last;
        }

        if($lines[$i] =~/^  (\S+)\s*(\S.*)/) {
            push(@item_name, $1);
            push(@item_desc, $2);
        } else {
            $lines[$i] =~s/^\s+|\s+$//g;
            $item_desc[$#item_desc] .= "$lines[$i] ";
        }
    }

    $$pi = $i - 1;
    return { item_name => \@item_name,
            item_desc => \@item_desc };
}

sub parse_vector {
    my $pi = shift;
    my @lines = @_;
    my $i = $$pi;

    my $str;
    for($i ++ ; $i < scalar(@lines); $i ++) {
        if($lines[$i] =~/^\w+:/) {
            last;
        }
        $lines[$i] =~s/^\s+|\s+$//g;
        $str .= $lines[$i];
    }

    $$pi = $i - 1;
    return [split qr/\s*,\s*/, $str];
}

# ``arg`` to \code{arg}
# `function` to \code{\link{function}}
# `package::function` to \code{\link[package]{function}}
sub trans_code {
    my $text = shift;
    
    $text =~s/``(.*?)``/\\code{$1}/g;
    
    $text =~s/`(.*?)`/
        my @a = split "::", $1;
        if(scalar(@a) == 2) {
            "\\code{\\link[$a[0]]{$a[1]}}";
        }
        else {
            "\\code{\\link{$a[0]}}";
        }
        /exg;
    return $text;
}

# http://xxx to \url{http:xxx}
sub trans_url {
    my $text = shift;

    $text =~s/(http|ftp|https)(:\/\/\S+)([\s\)\]\}\.,;:]*)/\\url{$1$2}$3/g;

    return $text;
}

__END__

=pod

=head1 NAME

R::Comment2DocDraft - transform comments in R code to .rd doc files

=head1 SYNOPSIS

  use R::Comment2DocDraft;
  
  R::Comment2DocDraft->draft("single.R");
  R::Comment2DocDraft->draft("R/");
  R::Comment2DocDraft->draft("single.R", author => 'Zuguang Gu <jokergoo@gmail.com>');

or by command line:

  r-comment2docdraft single.R
  r-comment2docdraft R
  r-comment2docdraft single author "Zuguang Gu <jokergoo@gmail.com>"

=head1 DESCRIPTION

When I am writing an R package, I find writing documents in man/ dir is really
boring. You need to tolerate hundreds of braces and be cautious to make sure
all the braces are matched correct. Also you need to add spaces at the begining
of some lines and make each line containing approximately 80 characters.
The more you are trying to make your tex code beautiful, the more chaos you will meet.
If there are some words need to be marked such as a \code{\link[]{}} mark,
the code would be difficult to read. Morever, if you change the function
arguments in .R file, I always forget chagne the corresponding part in .rd
files. It produces a lot of errors when checking the R package.

The R docs are written in LaTex format. Well, it is not friendly enough
for human to read. Also, seperating docs from codes is not convinient for
maintaining the package. A good way is to put the docs as comments with
the code. With some appointed simple formats, the comments would be easy 
to read and easy to convert to docs as well.

The idea is inspired by javadoc and MarkDown.

The module just produces a draft of .rd file because some sections are not
proper to be put in the comment such as the example section. So users
should edit the .rd file afterwards.

The format of the comment is really simple. The first line is the section name
and from the second line is the section content. such as

  # title:
  #   A function to calculate mean value

For some obsessive aesthetics, there should be one space in front of the 
section name and three spaces in front of the section content. Note that
the colon is necessary since we identify section name by it. Functions should
follow corresponding comments because we need to read the function names
and the function args.

There are some sections I think informative in comments. The list is
title, description, arguments, details, value, author, references, source,
seealso. Also name and docType should be added in data and package docs.
Except title section, all other sections are optional. 

=head2 Sections

Some sections do not need be set at every comment, such as author or
references. This kind of information can be set as a global variables.
See draft secton.

=over 4

=item text transformation

`function` will be converted to \code{\link{function}}

`package::function` will be converted to \code{\link[package]{function}}

``argument`` will be converted to \code{argument}

http|ftp|https:://xxx will be converted to \url{http|ftp|https://xxx}

=item title

Example is:

  # title:
  #   this is a function title

It will be converted as \title{content}. The title section should be places
as the first line of your comment to inform that the comment should be 
converted.

=item description

Example is:

  # description
  #   this is description, paragraph1
  #
  #   this is description, paragraph2

It will be converted as \description{content}.

=item usage

For function, the function name and the function args would be parsed from
source code, so users do not need to set it.

=item arguments

Example is: 

  # arguments:
  #   x first argument
  #   y second argument
  #   z third argument, line1,
  #     third argumetn, line2

It will be converted to 

  \arguments{
    \item{x}
      {first argument}
    \item{y}
      {second argument}
    \item{z}
      {third argument, line1, third argument, line2}
  }

Note we do not do any checking on the item list and the arguments in the function.

=item details

Example is:

  # details:
  #   this is a details, paragraph1
  #
  #   this is a details, paragraph2

It will be converted to 

  \details{
    this is a details, paragraph1
    
    this is a details, paragraph2
  }

=item value, value list

Example is:

  # value:
  #   the function returns a list
  #
  # valuelist:
  #   x vector
  #   y vector

It will be converted to

  \value{
    the function returns a list
    \item{x}{vector}
    \item{y}{vector}
  }

=item source

Example is:

  # source:
  #   http://url1
  #   http://url2

It will be converted to 

  \source{
    \url{http://url1}
    
    \url{http://url2}
  }

=item author

Example is:

  # author:
  #   jokergoo <at> gmail.com

It will be converted to

  \author{
    jokergoo <at> gmail.com
  }

=item references

Example is:

  # references:
  #   ref1
  #   ref2

It will be converted to 

  \references{
    ref1
    
    ref2
  }

=item seealso

Example is:

  # seealso
  #   `function1`, `function2`, `package::function3`

It will be converted to 

  \seealso{
    \code{\link{function1}}, \code{\link{function2}},
    \code{\link[package]{function3}}
  }

=back

=head2 Subroutines

=over 4

=item C<draft(file|dir, sectionname, sectionvalue, ...)>

The first parameter should be either a filename or a dir containing a list of R files.
the remaining parameters should be written as paris. The remaining parameters
can be thought of some global information such as author or references. But just
make sure the section name you set is a valid name since the module does not do
this kind of checkings. That will be checked by the R engine.

=back

=head2 Command line

=over 4

C<r-comment2docdraft> command is similar to C<draft> function. The first
argument is either a filename and a dir. other argument will be passed 
as section name and section value.

  r-comment2docdraft single.R
  r-comment2docdraft R
  r-comment2docdraft single.R author "Zuguang Gu <jokergoo@gmail.com>"

=back

=head1 TODO

convert comment mixed with paragraph and list.

if there already exist doc files, just update sections that have been changed.

=head1 AUTHOR

Zuguang Gu E<lt>jokergoo@gmail.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2012 by Zuguang Gu

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.12.1 or,
at your option, any later version of Perl 5 you may have available.

=cut
