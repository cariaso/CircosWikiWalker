#!/bin/env perl

use strict;
use warnings;
use MediaWiki::Bot;
use FileHandle;
use Data::Dumper;
use Memoize;
use Memoize::Storable;


package MediaWiki::Bot::Semantic;

use base 'MediaWiki::Bot';


sub ask {
    my $self     = shift;
    my $query    = shift;
    my $options  = shift;


    warn "Asking $query" if $self->{debug} > 1;

    my $hash = {
        'action'  => 'ask',
	'q'       => $query,
	'po'      => 'Special_need|In%20gene',
    };

    my $res = $self->{api}->api($hash, $options);
    return $res;
}



package GraphModel;

sub new {
    my ($class, $arg) = @_;
    my $self = bless {}, $class;
    return $self;
}

sub fake {
    my ($class, $arg) = @_;
    my $self = bless {}, $class;

    $self->link('bob','tree');
    $self->link('bob','pear');
    $self->link('bob','banana');
    $self->link('orange','pear');
    $self->link('orange','tree');
    $self->link('orange','person');
    $self->link('orange','banana');
    return $self;
}

sub names {
    my ($self) = @_;
    return sort keys %{$self->{_names}};

}

sub keyprep {
    my ($self, $s) = @_;
    return &main::circosSafeStr($s);
}

sub links {
    my ($self) = @_;
    my $scale = 5;
    my $sumfrom = {};
    my $name = 'link0001';
    my @out = ();
    foreach my $from (sort keys %{$self->{_links}}) {
	#my $safefrom = &main::circosSafeStr($from);
	my $safefrom = $from;
	foreach my $to (sort keys %{$self->{_links}->{$from}}) {
	    my $count = $self->{_links}->{$from}->{$to};
	    my $fromstart = $sumfrom->{$from} || 0;
	    my $fromend = $fromstart + $count*$scale;;
	    $sumfrom->{$from} = $fromend;
	    my $tostart = $sumfrom->{$to} || 0;
	    my $toend = $tostart + $count*$scale;;
	    $sumfrom->{$to} = $toend;


	    #my $safeto = &main::circosSafeStr($to);
	    my $safeto = $to;
	    my $text = "$name $safefrom $fromstart $fromend\n$name $safeto $toend $tostart\n";
	    $name++;
	    push @out, $text;
	}
    }

    $self->{_size} = $sumfrom;
    return @out;
}

sub link {
    my ($self, $from, $to) = @_;
    my $sfrom = $self->keyprep($from);
    my $sto = $self->keyprep($to);

    $self->{_links}->{$sfrom}->{$sto}++;
    $self->{_names}->{$sfrom}++;
    $self->{_names}->{$sto}++;

}


sub size {
    my ($self, $name) = @_;
    my $sname = $self->keyprep($name);
    return $self->{_size}->{$sname};
}


package main;



sub circosSafeStr {
    my ($s) = @_;
    $s =~ s/[ \/\:\(\)\'\"\,\;\#=]/_/g;
    $s =~ s/_+//g;
    #$s =~ s/_+$//g;
    return $s;
}


my %cache1;
#tie %cache1 => 'Memoize::Storable', './wlhmemory.tmp';
memoize('whatLinksHere', 
	LIST_CACHE => [HASH => \%cache1],
	NORMALIZER => 'normalize_f');


sub normalize_f {
    my ($bot, $page) = @_;
    return $page;
}


sub whatLinksHere {
    my ($bot, $page) = @_;
    print "in wlh($page)\n";
    my @refs = $bot->what_links_here($page,undef, [0,1]);
    return @refs;
}


my %cache2;
#tie %cache2 => 'Memoize::Storable', './flmemory.tmp';
memoize('forwardLinks', 
	LIST_CACHE => [HASH => \%cache2],
	NORMALIZER => 'normalize_f');


sub forwardLinks {
    my ($bot, $title) = @_;
    print "in fL($title)\n";
    my $text = '';
    eval {
	$text = $bot->expandtemplates($title);
    };
    if ($@) {
	
	#$text = $bot->get_text($title);

    }
    my @brackets = $text =~ /(\[\[.*?\]\])/g;

    my @fwdlinks;
    foreach my $link (@brackets) {
	print "consider $link\n";
	if ($link =~ /\|/) {
	    push @fwdlinks, $link =~ /\[\[:?([^|]+)/;
	} else {
	    push @fwdlinks, $link =~ /\[\[:?(.*)\]\]/;
	}
    }
    return @fwdlinks;
}





sub crawl2 {
    my ($bot, $page, $state) = @_;
    print "in crawl2($page)\n";
    #my $count = $state->{count};
    my $graph = $state->{graph};


    
    my @fwdrefs = forwardLinks($bot, $page);
    foreach my $fwdref (@fwdrefs) {
	#$count->{$fwdref}++;
	print "\t$page => $fwdref\n";
	$graph->link($page, $fwdref);
    }

    my @otherrefs = whatLinksHere($bot, $page);
    foreach my $otherref (@otherrefs) {
	#$count->{$otherref->{title}}++;
	print "\t$page <- $otherref->{title}\n";
	$graph->link($otherref->{title}, $page);
	
    }

}


sub crawl {
    my ($bot, $starttitle) = @_;
    print "in crawl($starttitle)\n";
    my $out = {};
    my $outfn = 'thelinks.dat';
    my $depth = 'very';

    my $graph = GraphModel->new();
    my $count = {};
    my $state = {count=>$count,
		 graph=>$graph};


    my @outboundrefs = forwardLinks($bot, $starttitle);
    foreach my $fwdref (@outboundrefs) {
	$graph->link($starttitle, $fwdref);
	#$count->{$fwdref}++;
	print "$starttitle -> $fwdref\n";
	crawl2($bot, $fwdref, $state);

    }
    my @inboundrefs = whatLinksHere($bot, $starttitle);
    foreach my $inref (@inboundrefs) {
	$graph->link($inref->{title}, $starttitle);
	#$count->{$inref->{title}}++;
	print "$starttitle <- $inref->{title}\n";
	crawl2($bot, $inref->{title}, $state);
    }

    return $graph
}


sub makeKaryotype {
    my ($fn, $graph) = @_;
    my $fh = FileHandle->new(">$fn") or warn($!);
    binmode $fh, ":utf8";
    
    my $maxnames = 50;
    my $sizes = {};
    foreach my $name ($graph->names) {
	my $size = $graph->size($name);
	push @{$sizes->{$size}}, $name;
    }

    my $numprinted = 0;
    foreach my $size (sort {$sizes->{$b} <=> $sizes->{$a}} keys %$sizes) {
	foreach my $name (@{$sizes->{$size}}) {
	    if ($numprinted < $maxnames) {
		my $safename = circosSafeStr($name);
		print $fh "chr - $safename $safename 0 $size chrUn\n";
		$numprinted++;
	    }
	}
    }

}


sub makeLinks {
    my ($fn, $graph) = @_;



    my $fh = FileHandle->new(">$fn") or warn($!);
    binmode $fh, ":utf8";
    
    foreach my $text ($graph->links) {
	print $fh $text;
	#my $safename = circosSafeStr($name);
	#my $size = $graph->size($name);
	#print $fh "chr - $safename $safename 0 $size chrUn\n";

    }

}


sub makeCircosImage {
    my ($bot, $title, $imagefn) = @_;

    my $conffn = 'topcircos.conf';
    my $conffh = FileHandle->new(">$conffn") or warn($!);


    my $linksdatafn = 'myribbons.txt';



    my $graph = crawl($bot, $title);
    #my $graph = GraphModel->fake();
    makeLinks($linksdatafn, $graph);



    my $linkstext = <<"ENDLINKSCONF";
<links>

z      = 0
radius = 0.99r
crest  = 1
color  = grey
bezier_radius        = 0.2r
bezier_radius_purity = 0.5

<link segdup>
thickness    = 2
ribbon       = yes
stroke_color = vdgrey
stroke_thickness = 2
file         = ${linksdatafn}

<rules>

flow = continue


<rule>
importance = 200
condition  = max(_SIZE1_,_SIZE2_) < 3
show = no
</rule>

#<rule>
#importance = 125
#condition  = _INTRACHR_ && ((_CHR1_ eq "slang") || (_CHR2_ eq "Peru"))
#color = orange
#stroke_color = dorange
#</rule>

<rule>
importance = 120
condition  = _INTRACHR_ && ((_CHR1_ eq "SNPedia") || (_CHR2_ eq "SNPedia"))
color = lref
stroke_color = dred
</rule>

<rule>
importance = 115
condition  = _INTRACHR_ && ((_CHR1_ eq "United Nations") || (_CHR2_ eq "United Nations"))
color = lblue
stroke_color = dblue
</rule>

</rules>

</link>

</links>

ENDLINKSCONF


    my $snpfn = 'snpfn.dat';
    my $toplevel = '';
    my $karyotypefn = 'mykaryo.dat';

    #my $graph = crawl($bot, $title);
    #my $graph = GraphModel->new();
    makeKaryotype($karyotypefn, $graph);

    my $imagfn = 'animage.png';


    print $conffh <<"ENDMAINCONF";

<colors>
<<include etc/colors.conf>>
<<include etc/brewer.conf>>
</colors>

<fonts>
<<include etc/fonts.conf>>
</fonts>


<ideogram>
show = yes

<spacing>
default = 0.005r
break   = 0.5u
</spacing>



radius           = 0.70r
thickness        = 100p
fill             = yes
fill_color       = black
stroke_thickness = 2
stroke_color     = black

show_label       = yes
label_font       = bold
label_radius     = dims(ideogram,radius) + 0.07r
label_with_tag   = yes
label_size       = 36
label_parallel   = no
show_bands            = yes
fill_bands            = yes
band_stroke_thickness = 2
band_stroke_color     = white
band_transparency     = 2

</ideogram>


show_ticks          = yes
show_tick_labels    = yes

<ticks>
skip_first_label = no
skip_last_label  = no
radius           = dims(ideogram,radius_outer)
tick_separation  = 3p
label_separation = 1p
multiplier       = 1e-6
color            = black
thickness        = 4p
size             = 20p

<tick>
spacing        = 1u
show_label     = no
thickness      = 2p
color          = dgrey
</tick>

<tick>
spacing        = 5u
show_label     = no
thickness      = 3p
color          = vdgrey
</tick>

<tick>
spacing        = 10u
show_label     = yes
label_size     = 20p
label_offset   = 10p
format         = %d
grid           = yes
grid_color     = dgrey
grid_thickness = 1p
grid_start     = 0.5r
grid_end       = 0.999r
</tick>

</ticks>


<image>
dir   = circos
file  = ${imagefn}
png   = yes
#svg   = yes
# radius of inscribed circle in image
radius         = 1500p
#radius         = 500p

# by default angle=0 is at 3 o'clock position
#angle_offset   = 240
angle_offset   = -240

#angle_orientation = counterclockwise

auto_alpha_colors = yes
auto_alpha_steps  = 50

background = white
</image>

# specify the karyotype file here - try other karyotypes in data/karyotype
karyotype = ${karyotypefn}

chromosomes_units           = 1000000
#chromosomes_units           = 100000



chromosomes_display_default = yes
#chromosomes        = hs19;hs20;hsMedical
#chromosomes        = hs15:250-265;
#chromosomes_display_default = no
#chromosomes_radius = hsMedical:1.25r;
${toplevel}

<highlights>
z          = 5
ideogram   = yes
fill_color = orange
</highlights>



<plots>

<plot>
show = no
type       = text
file       = ${snpfn}

#url              = http://www.snpedia.com/index.php/[label]
color            = black

label_snuggle             = yes
max_snuggle_distance      = 2r
snuggle_sampling          = 2
snuggle_tolerance         = 0.25r
snuggle_link_overlap_test = yes 
snuggle_link_overlap_tolerance = 2p
#snuggle_refine            = yes
snuggle_refine            = no



r0 = 1r
r1 = 1r+400p

show_links     = yes
link_dims      = 0p,0p,50p,0p,10p
link_thickness = 2p
link_color     = red

label_size   = 18p
label_font   = condensed

padding  = 0p
rpadding = 0p

</plot>


</plots>





${linkstext}




<<include etc/housekeeping.conf>>

ENDMAINCONF







    system("circos/merged/bin/circos --conf $conffn");




    #my $graph = crawl($bot, $title);

}









# example url for your browser
# http://snpedia.com/api.php?action=ask&q=[[In%20gene::STAT4]][[Category:Has%20a%20neighbor]]&po=In%20gene|On%20chromosome

my $bot = MediaWiki::Bot->new();
$bot->set_wiki('snpedia.com','/');


my $old = $bot->get_text('User:Cariaso');
$bot->edit('User:Cariaso', "${old}.");

exit;

my $request = {
        'action'  => 'ask',

        # a query in the usual SMW ask synax        {{#ask:q}}
	'q'       => "[[In gene::STAT4]] [[Category:Has a neighbor]]",
	#'q'       => "[[Category:Is a snp]]",

        # not yet accessible from Perl, but these extra fields will be sent along from the server
	'po'      => 'In gene|On chromosome', 
};
my $options = {};
$bot->{api}->{use_http_get} = 0;
$bot->{api}->{use_http_post} = 1;

my $response = $bot->{api}->api($request, $options);
#print Dumper $response;
my @items = @{$response->{ask}->{results}->{items}};
print "\n-=-=-=-=-=-=-=-=-=-=-=\n";
foreach my $item (@items) {
    my $name = $item->{title}->{mTextform};
    print "$name\n";
}














__END__



#makeCircosImage($bot, 'User:Cariaso', 'wikipedia-Cariaso.png');
#makeCircosImage($bot, 'ARMD', 'snpedia-ARMD.png');

binmode STDOUT, ":utf8";
my $bot = MediaWiki::Bot->new();
$bot->set_wiki('en.wikipedia.org','/w/');


makeCircosImage($bot, 'User:Cariaso', 'wikipedia-Cariaso.png');

#makeCircosImage($bot, 'Semantic_MediaWiki', 'Semantic_MediaWiki.png');
#makeCircosImage($bot, 'Berlin', 'Berlin.png');
#makeCircosImage($bot, 'Miami', 'Miami.png');
#makeCircosImage($bot, 'Bangkok', 'Bangkok.png');
#makeCircosImage($bot, 'Yerevan', 'Yerevan.png');

Memoize::unmemoize 'whatLinksHere';
Memoize::unmemoize 'forwardLinks';

