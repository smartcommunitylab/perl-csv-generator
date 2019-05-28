#! perl -w

use strict;
use utf8;
use List::MoreUtils qw{ any };

use open ':encoding(utf8)';

my $DEBUG = 0;

my $csvdelim = ';';
my $csvescape = '';

my @routes = ('P-01_A','P-01_R','P-02_A','P-02_R','P-03_A','P-03_R','P-04_A','P-04_R','P-05_A','P-05_R','P-06_A','P-06_R','P-07_A','P-07_R','P-%20A_C','P-%20B_C','P-%20V_A','P-%20V_R','P-AB_A','P-AB_R','N-01_A','N-01_R','N-02_A','N-02_R','N-03_A','N-03_R','N-06_A','N-06_R');

my @routes_feriale = ('P-01_A','P-01_R','P-02_A','P-02_R','P-03_A','P-03_R','P-04_A','P-04_R','P-05_A','P-05_R','P-06_A','P-06_R','P-07_A','P-07_R','P-%20A_C','P-%20B_C','P-%20V_A','P-%20V_R','N-01_A','N-01_R','N-02_A','N-02_R','N-03_A','N-03_R','N-06_A','N-06_R');

my @routes_festivo = ('P-02_A','P-02_R','P-06_A','P-06_R','P-AB_A','P-AB_R');

#@routes = ('P-01_A');
#@routes_feriale = ('P-01_A');
#@routes_festivo = ();

my $BASE_TTE_URL = "https://www.trentinotrasporti.it/pdforari/urbani/linee";
my $BASE_TTE_NAME = "OrariDiDirettrice-R18R-";

#########################################################

my %routesinfo;
my %stopsinfo;

foreach my $route (@routes) {
  if (any { $_ eq $route} @routes_feriale) {
#    extract_route("$route-Feriale","$route-Feriale");
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
        die;
      }
      $page_xml = $1;
      if ($DEBUG) { print STDERR "    Page: $page_xml\n"; }
    } elsif (/\<text top\=\"(.*)\" left=\"(.*)\" width=\".*\" height=\".*\" font=\".*\"\>(.*)\<\/text\>/) {
      if ($page_xml == 0) {
        print STDERR "Text outside pages\n";
        die;
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
      die;
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
  my $xmlfile = "xml-Rovereto/$longname.xml";
  my $csvfile = "csv-Rovereto/$linename.csv";
  my $timefile = "gtfs/stop_times_$linename.txt";
  my $tripsfile = "gtfs/trips_$linename.txt";
  my $legsfile = "legs/legs_$linename.txt";

  if (! -f "pdf-Rovereto/$longname.pdf") {
    print STDERR "WGETTING PDF of $linename ($BASE_TTE_URL/$longname.PDF)\n";   
    if (system("wget -O pdf-Rovereto/$longname.pdf $BASE_TTE_URL/$longname.PDF") != 0) {
      my $save = $?;
      unlink ("pdf-Rovereto/$longname.pdf");
      die "WGET failed: $save"
    }
  }

  if (! -f $xmlfile) {
    print STDERR "XMLLING $linename\n";
    if (system("pdftohtml -xml pdf-Rovereto/$longname.pdf xml-Rovereto/$longname") != 0) {
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

    if ($text =~ /<b>(ORARIO Rovereto Inv. 2019   Valido dal ..\/..\/2019 al 08\/06\/2019 )<\/b>/) {
      $routesinfo{$routename}->{'validity'} = normalize($1);
    } else { 
      print STDERR "ERRORE INTESTAZIONE (Validità): $text\n";
      die;
    }

    ($top,$left,$text) = get_next_line_xml();
    if (($text ne "<b>ORARIO FERIALE</b>") && ($text ne "<b>ORARIO FESTIVO</b>")) {
      print STDERR "ERRORE INTESTAZIONE (Feriale/Festivo): $text";
      die;
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
      die;
    }

    ($top,$left,$text) = get_next_line_xml();

    if ($text =~ /<b>(.*)<\/b>/) {
      if ($page_xml == 1) {
          $routesinfo{$routename}->{'short_descr'} = $1;
      }
    } else {
      print STDERR "ERRORE INTESTAZIONE (LineNo): $text";
      die;
    }

    ($top,$left,$text) = get_next_line_xml();

    { # manage frequenza
      if ($text ne "<b>Frequenza</b>") {
        print STDERR "ERRORE INTESTAZIONE (Frequenza): $text\n";
        die;
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
        die;
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
          #print "ADD STAZIONE: >$fermata<\n";
      } else {
        if ($rownames[$rownum] ne $fermata) {
          print "ERRORE NOME STAZIONE: >" . $rownames[$rownum] . "< >$fermata<\n";
          die;
        }
        %row = %{$rows[$rownum]};
      }

      while (1) {
        ($top,$left,$text) = get_next_line_xml();
        if (abs($top-$savetop)>5) {
          if ($top < $savetop) { print "RIGA FUORI ORDINE: $top < $savetop\n"; die; }
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
          die;
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
        die;
      }
    }

    ($top,$left,$text) = get_next_line_xml();
    if ($text !~ /<i>Pag.*<\/i>/) {
      print "ERRORE FINALE: $text\n";
      die;
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
      die; 
    };
    if (abs($top-$savetop)>5) {
      print STDERR "Alignment problem of symbol and text in Frequenze ($symbol: $text)\n";
      die; 
    }
    if (defined($symbols{$symbol})) {
      print STDERR "Redefining symbol in Frequenze or Note ($symbol)\n";
      die; 
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
        die;
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
          if ($colinfo{$n} =~ /<b>(([0-9]+|N[0-9]+|NP|A|B|C|D|P|S)\/?)<\/b>/) {
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

