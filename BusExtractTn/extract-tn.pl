#! perl -w

use strict;
use utf8;
use List::MoreUtils qw{ any };

use open ':encoding(utf8)';

my $DEBUG = 0;

my $csvdelim = ';';
my $csvescape = '';

my @routes = ('01_A','01_R','02_C','03_A','03_R','04_A','04_R','05_A','05_R','05_b','06_A','06_R','07_A','07_R','08_A','08_R','09_A','09_R','10_A','10_R','11_A','11_R',
              '12_A','12_R','13_A','13_R','14_A','14_R','15_A','15_R','16_A','16_R','17_A','17_R','NP_C','%20A_C','%20B_C','%20C_A','%20C_R','%20G_A','%20G_R','CM_A','CM_R');

my @routes_feriale = @routes;

my @routes_festivo = ('01_A','01_R','02_C','03_A','03_R','04_A','04_R','05_A','05_R',    '06_A','06_R',              '08_A','08_R',              '10_A','10_R',              
              '12_A','12_R',                                                        '17_A','17_R',       '%20A_C');

#@routes = ('11_A');
#@routes_festivo = ();
#@routes_feriale = @routes;

my $BASE_TTE_URL = "https://www.trentinotrasporti.it/pdforari/urbani/linee";
my $BASE_TTE_NAME = "OrariDiDirettrice-T18I-T-";

#########################################################

my %routesinfo;
my %stopsinfo;

foreach my $route (@routes) {
  if (any { $_ eq $route} @routes_feriale) {
    eval { extract_route("$route-Feriale","$route-Feriale"); }; warn $@ if $@;
  }
  if (any { $_ eq $route} @routes_festivo) {
#    extract_route("$route-Festivo","$route-Festivo");
    eval { extract_route("$route-Festivo","$route-Festivo"); }; warn $@ if $@;
  }
}

exit;

#########################################################

my $page_xml;

sub open_xml {
  my ($xmlfile) = @_; 
  open (XMLN, "<utf8", $xmlfile)
    or die "Cannot open: " . $xmlfile;
  $page_xml = 0;
}

sub get_next_line_xml {
  while (<XMLN>) {
    if (/\<page number="([0-9]*)".*/) {
      if ($1 != $page_xml + 1) {
        print STDERR "Pages out of order: $page_xml, $1\n";
        exit;
      }
      $page_xml = $1;
      if ($DEBUG) { print STDERR "    Page: $page_xml\n"; }
    } elsif (/\<text top\=\"(.*)\" left=\"(.*)\" width=\".*\" height=\".*\" font=\".*\"\>(.*)\<\/text\>/) {
      if ($page_xml == 0) {
        print STDERR "Text outside pages\n";
        exit;
      }
      if ($3 eq "<b> </b>") { next; }
      if ($DEBUG > 3) { print STDERR $_; }
      return ($1,$2,$3);
    }
  }
}

sub close_xml {
  close (XMLN);
}

#########################################################

#! perl -w

use LWP::UserAgent;
use HTTP::Request::Common;

sub getstops {
  my $ua = LWP::UserAgent->new;
  my $r = $ua->get("http://www.arcoda.it/tt/default.htm");

  if (! $r->is_success) {
     die "MAP GET ERROR: " . $r->status_line;
  }

  for (split /^/, $r->decoded_content) {
    if (/<marker[0-9] name='(.*)' lat='(.*)' lng='(.*)' id='(.*)' k_nodo='(.*)' url_code='(.*)' image_name='(.*)' routes='(.*)'\/>/) {
      if (defined($stopsinfo{$4})) {
        if (($stopsinfo{$4}->{'name'} ne $1) || ($stopsinfo{$4}->{'lat'} ne $2) || ($stopsinfo{$4}->{'lng'} ne $3) || ($stopsinfo{$4}->{'k_nodo'} ne $5)) {
          print STDERR "Duplicate marker error: $4";         
        }
      } else {
        $stopsinfo{$4} = { 'name' => $1, 'lat' => $2, 'lng' => $3, 'k_nodo' => $5 };
      }
    } elsif (/<marker[0-9] /) {
      print STDERR "Marker error: $_";
      exit;
    }
  }
}


sub normalize {
  my ($name) = @_;
  $name =~ s/ +$//;
  $name =~ s/^ +//;
  $name =~ s/&apos;/'/g;
  $name =~ s/&quot;/"/g;
  $name =~ s/&#34;/"/g;
  return $name;
}

sub extract_route {

  my ($routename,$linename) = @_; 

  my $longname = "$BASE_TTE_NAME$linename";
  my $xmlfile = "xml-Trento/$longname.xml";
  my $csvfile = "csv-Trento/$linename.csv";
  my $timefile = "gtfs/stop_times_$linename.txt";
  my $tripsfile = "gtfs/trips_$linename.txt";
  my $legsfile = "legs/legs_$linename.txt";

  if (! -f "pdf-Trento/$longname.pdf") {
    print STDERR "WGETTING PDF of $linename ($BASE_TTE_URL/$longname.PDF)\n";   
    if (system("wget -O pdf-Trento/$longname.pdf $BASE_TTE_URL/$longname.PDF") != 0) {
      my $save = $?;
      unlink ("pdf-Trento/$longname.pdf");
      die "WGET failed: $save"
    }
  }

  if (! -f $xmlfile) {
    print STDERR "XMLLING $linename\n";
    if (system("pdftohtml -xml pdf-Trento/$longname.pdf xml-Trento/$longname") != 0) {
      die "TOXML failed: $?"
    }
  }

  print STDERR "EXTRACTING LINE: $linename\n";

  my ($top,$left,$text);
  my $savetop;
  my $defaultcal;

  my @codicifermate = [];
  my %symbols;

  my @columns;
  my @rownames;
  my @rows;
  my %rowlineinfo;

  open_xml($xmlfile);

  while(1) {

    ($top,$left,$text) = get_next_line_xml();

    if ($text =~ /<b>(ORARIO Trento Inverno 2018-19   Valido dal ..\/09\/2018 al 08\/06\/2019 )<\/b>/) {
      $routesinfo{$routename}->{'validity'} = normalize($1);
    } else { 
      print STDERR "ERRORE INTESTAZIONE (Validità): $text\n";
      exit;
    }

    ($top,$left,$text) = get_next_line_xml();
    if (($text ne "<b>ORARIO FERIALE</b>") && ($text ne "<b>ORARIO FESTIVO</b>")) {
      print STDERR "ERRORE INTESTAZIONE (Feriale/Festivo): $text";
      exit;
    }

    if ($page_xml == 1) {
      if ($text eq "<b>ORARIO FERIALE</b>") {
        $routesinfo{$routename}->{'orario'} = "ORARIO FERIALE";
        $defaultcal = "Feriale";
      } else {
        $routesinfo{$routename}->{'orario'} = "ORARIO FESTIVO";
        $defaultcal = "Festivo";
      }
    }

    ($top,$left,$text) = get_next_line_xml();

    if ($text =~ /<b>(.*)<\/b>/) {
      if ($page_xml == 1) {
          $routesinfo{$routename}->{'long_descr'} = normalize($1);
      }
    } else {
      print STDERR "ERRORE INTESTAZIONE (Descrizione): $text";
      exit;
    }

    ($top,$left,$text) = get_next_line_xml();

    if ($text =~ /<b>(.*)<\/b>/) {
      if ($page_xml == 1) {
          $routesinfo{$routename}->{'short_descr'} = $1;
      }
    } else {
      print STDERR "ERRORE INTESTAZIONE (LineNo): $text";
      exit;
    }

    ($top,$left,$text) = get_next_line_xml();

    { # manage frequenza
      if ($text ne "<b>Frequenza</b>") {
        print STDERR "ERRORE INTESTAZIONE (Frequenza): $text\n";
        exit;
      }

      $savetop = $top;

      my %row;

      if ($page_xml != 1) {
         %row = %{$rows[0]};
      }

      while (1) {
        ($top,$left,$text) = get_next_line_xml();
        if (abs($top-$savetop)>5) {
          last;
        }
        my $col = $left + $page_xml*1000;
        $row{$col} = $text;
        if (!($col ~~ @columns)) {
          @columns = (@columns, $col);
        }
      }
      %{$rows[0]} = %row;
    }

    { # manage linea
      if ($text ne "<b>Linea</b>") {
        print STDERR "ERRORE INTESTAZIONE (Linea): $text";
        exit;
      }

      $savetop = $top;

      my %row;

      if ($page_xml != 1) {
         %row = %rowlineinfo;
      }

      while (1) {
        ($top,$left,$text) = get_next_line_xml();
        if (abs($top-$savetop)>5) {
          last;
        }
        my $col = $left + $page_xml*1000;
        $row{$col} = $text;
        if (!($col ~~ @columns)) {
          @columns = (@columns, $col);
        }
      }

      %rowlineinfo = %row;
    }

    my $rownum = 0;

    while (($text ne "Le note dei simboli sono sull'ultima pagina di ogni linea") && ($text ne "<b>Frequenze</b>") && ($text ne "<i>www.eureka.ra.it</i>")) {
      $savetop = $top;  

      $rownum++;
      my $fermata = $text;

      my %row;
      if (($page_xml == 1) || ($rownum > $#rownames)) {
        $rownames[$rownum] = $fermata;
      } else {
        if ($rownames[$rownum] ne $fermata) {
          print "ERRORE NOME STAZIONE: >$fermata<\n";
          exit;
        }
        %row = %{$rows[$rownum]};
      }

      while (1) {
        ($top,$left,$text) = get_next_line_xml();
        if (abs($top-$savetop)>5) {
          last;
        }
        my $col = $left + $page_xml*1000;
        if ($text eq "  |  ") {
          $row{$col} = $text;
        } elsif ($text =~ /^(..\...)$/) {
          $row{$col} = $1;
        } elsif ($text =~ /^<i>(..\...)<\/i>$/) {
          $row{$col} = "-" . $1;
        } else {
          print STDERR "Time format error: $text\n";
          exit;
        }
        if (!($col ~~ @columns)) {
          @columns = (@columns, $col);
        }
      }

      $rows[$rownum] = \%row;
    }

    if ($text eq "<b>Frequenze</b>") {
      last;
    }

    if ($text ne "<i>www.eureka.ra.it</i>") {
      ($top,$left,$text) = get_next_line_xml();
      if ($text ne "<i>www.eureka.ra.it</i>") {
        print "ERRORE FINALE: $text\n";
        exit;
      }
    }

    ($top,$left,$text) = get_next_line_xml();
    if ($text !~ /<i>Pag.*<\/i>/) {
      print "ERRORE FINALE: $text\n";
      exit;
    }

  }

  while (1) { # Manage frequenze and note
    ($top,$left,$text) = get_next_line_xml();
    if ($text eq "<b>Note di Corsa</b>") {
      next;
    }
    if ($text eq "<i>www.eureka.ra.it</i>") { 
      last 
    };
    my $symbol = $text;
    $savetop = $top;

    ($top,$left,$text) = get_next_line_xml();
    if (($text eq "<b>Note di Corsa</b>") || ($text eq "<i>www.eureka.ra.it</i>")) { 
      print STDERR "Symbol without text in Frequenze or Note\n";
      exit; 
    };
    if (abs($top-$savetop)>5) {
      print STDERR "Alignment problem of symbol and text in Frequenze ($symbol: $text)\n";
      exit; 
    }
    if (defined($symbols{$symbol})) {
      print STDERR "Redefining symbol in Frequenze or Note ($symbol)\n";
      exit; 
    }
    $symbols{$symbol} = $text;
  }

  close_xml();

######################################

  @columns = sort {$a <=> $b} @columns;

  my $last = 0;
  my $col = 1;
  my %columnsmap;

  foreach my $c (@columns) {
    if ($c - $last <= 25) {
      $columnsmap{$c} = $columnsmap{$last};
    } else {
      $columnsmap{$c} = $col++;
      $last = $c;
    }
  }

  my %colinfo;

  foreach my $ci (keys %rowlineinfo) {
    $colinfo{$columnsmap{$ci}} = $rowlineinfo{$ci};
  }

  my %coltripid;
  my %idtrip;


  open (CSVOUT,">$csvfile") or die "Cannot open: " . $csvfile;

  my @timesarray;
  my @tripsarray;

  print CSVOUT "Descr.breve:${csvdelim}${csvescape}$routesinfo{$routename}->{'short_descr'}\n";
  print CSVOUT "Descr.lunga:${csvdelim}${csvescape}$routesinfo{$routename}->{'long_descr'}\n";
  print CSVOUT "Validità:${csvdelim}${csvescape}$routesinfo{$routename}->{'validity'}\n";
  print CSVOUT "Orario:${csvdelim}${csvescape}$routesinfo{$routename}->{'orario'}\n";

  my %coltrips;

  for (my $rn = 0; $rn <= $#rownames; $rn++) {
    my %row = %{$rows[$rn]};
    my @ks = sort {$a <=> $b} keys(%row);
    my $n = 0;
    if ($rn > 0) {
      print CSVOUT normalize($rownames[$rn]);
    } else {
      print CSVOUT "Frequenza:";
    }
    foreach my $k (@ks) {
      if ($columnsmap{$k} <= $n) {
        print STDERR "CLASH COLONNE: $n\n";
        exit;
      }  
      while ($n < $columnsmap{$k}) {
        print CSVOUT "${csvdelim}";
        $n++;
      }
      if ($rn > 0) {
        my $time = $row{$k};
        if ($time =~ /^(-?)00.([0-9][0-9])$/) {
          #print STDERR "00->24\n";
          print CSVOUT "${csvescape}${1}24.$2";
        } elsif ($time =~ /^(-?)01.([0-9][0-9])$/) {
          #print STDERR "01->25\n";
          print CSVOUT "${csvescape}${1}25.$2";
        } else {
          print CSVOUT "${csvescape}$time";
        }
      } else {
        print CSVOUT "${csvescape}$symbols{$row{$k}}";
      }
    }
    print CSVOUT "\n"; 
    if ($rn == 0) {
      print CSVOUT "Linea:";
      for (my $n = 1; $n < $col; $n++) {
        if (defined $colinfo{$n}) { 
          if ($colinfo{$n} =~ /<b>(([0-9]+|NP|A|B|C|CM|G)\/?)<\/b>/) {
            print CSVOUT "${csvdelim}${csvescape}Linea $1";
          } elsif (defined($symbols{$colinfo{$n}})) {
            print CSVOUT "${csvdelim}${csvescape}$symbols{$colinfo{$n}}";
          } else {
            print CSVOUT "${csvdelim}${csvescape}$colinfo{$n}";
            print STDERR "UNKNOWN LINEA SYMBOL $colinfo{$n}\n";
          }
        } else {
          print CSVOUT "${csvdelim}";
        }
      }
      print CSVOUT "\n";
      print CSVOUT "Servizio:\n";
    }
  } 

  close (CSVOUT);

}

