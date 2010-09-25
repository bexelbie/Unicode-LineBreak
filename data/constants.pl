#! perl

my $LINEBREAK_H = '';
my $LBCLASSES = '';

my @attr = split /,/, shift @ARGV;
foreach my $attr (@attr) {
    my $OMIT;
    my @classes;
    my $datafile;

    if ($attr eq 'lb') {
	$OMIT = qr{AI|SA|SG|XX|...};
	@classes = qw{BK CR LF NL SP
	    OP CL QU GL NS EX SY IS PR PO NU AL ID IN HY BA BB B2 CB ZW CM WJ
	    H2 H3 JL JV JT
	    SG AI SA XX};
	$datafile = 'LineBreak';
    } elsif ($attr eq 'ea') {
	$OMIT = undef;
	@classes = qw{Z Na N A W H F};
	$datafile = 'EastAsianWidth';
    } elsif ($attr eq 'sc') {
	$OMIT = undef;
	@classes = qw(Common Inherited Unknown Han Hangul);
	$datafile = 'Scripts';
    } elsif ($attr eq 'gb') {
	$OMIT = undef;
	@classes = qw(CR LF Control Extend Prepend SpacingMark L V T LV LVT Other);
	$datafile = 'GraphemeBreakProperty';
    } else {
	die "Unknown attr $attr\n";
    }

    my @versions = sort { cmpversion($a, $b) } @ARGV;

    my %classes = map { ($_ => '') } @classes;

    foreach my $version (@versions) {

	my %SA = ();
	foreach my $ext ('custom', 'txt') {
	    open LB, '<', "LineBreak-$version.$ext" or next;
	    while (<LB>) {
		chomp $_;
		s/\s*#.*$//;
		next unless /\S/;
		my ($code, $prop) = split /;/;
		$code = hex("0x$code");
		$SA{$code} = 1 if $prop eq 'SA';
	    }
	    close LB;
	}

	# read new classes from rules.
	if ($attr eq 'lb') {
	    unless (open RULES, '<', "Rules-$version.txt") {
		die $!;
	    }
	    while (<RULES>) {
		chomp $_;
		s/#.*//;
		next unless /\S/;
		foreach my $c (m/(\b[A-Z][0-9A-Z]\b)/g) {
		    unless (defined $classes{$c}) {
			push @classes, $c;
			$classes{$c} = $version;
		    }
		}
	    }
	    close RULES;
	}
	# read new classes from data.
	foreach my $data (("$datafile-$version.txt",
			   "$datafile-$version.custom")) {
	    unless (open DATA, '<', $data) {
		die $! unless $data =~ /\.custom$/;
		next;
	    }
	    while (<DATA>) {
		chomp $_;
		s/\s*#.*//;
		next unless /\S/;
		my ($ucs, $c) = split /;\s*/, $_;

		next unless $ucs;
		my ($beg, $end) = split /\.\./, $ucs;
		my ($beg, $end) = split /\.\./, $ucs;
		$end ||= $beg;
		$beg = hex("0x$beg");
		$end = hex("0x$end");

		next unless $c =~ /^\w+$/;
		foreach my $chr (($beg..$end)) {
		    next if $attr eq 'sc' and !$SA{$chr}; # limit to SA
		    unless (defined $classes{$c}) {
			push @classes, $c;
			$classes{$c} = $version;
		    }
		}
	    }
	    close DATA;
	}

	my @indexedclasses;
	if ($OMIT) {
	    @indexedclasses = grep(!/$OMIT/, @classes);
	    @classes = (@indexedclasses, grep(/$OMIT/, @classes));
	} else {
	    @indexedclasses = @classes;
	}
	$indexedclasses{$attr} ||= {};
	$indexedclasses{$attr}->{$version} = [@indexedclasses];
    }

    my $i;
    for ($i = 0; $i <= $#classes; $i++) {
	$LINEBREAK_H .= "#define ".uc($attr)."_$classes[$i] ((propval_t)$i)\n";
    }
    $LINEBREAK_H .= "\n";
}

$LBCLASSES .= "\%indexedclasses = (\n";
foreach my $attr (@attr) {
    $LBCLASSES .= "    '$attr' => {\n";
    foreach my $version (sort { cmpversion($a, $b) }
			 keys %{$indexedclasses{$attr}}) {
	$LBCLASSES .= "        '$version' => [qw(".
	    join(' ', @{$indexedclasses{$attr}->{$version}}).
	    ")],\n";
    }
    $LBCLASSES .= "    },\n";
}
$LBCLASSES .= ");\n\n1;\n";

open LINEBREAK_H, '>', '../linebreak/include/linebreak_constants.h' or die $!;
open LBCLASSES, '>', 'LBCLASSES' or die $!;

open IN, '<', 'linebreak_constants.h.in' || die $!; $_ = join '', <IN>; close IN;
s/([^\n]*<<<[^\n]*)(.*)(\n[^\n]*>>>[^\n]*)/$1\n$LINEBREAK_H$3/s;
print LINEBREAK_H $_;
close LINEBREAK_H;

print LBCLASSES $LBCLASSES;
close LBCLASSES;

sub cmpversion {
    my $x = sprintf '%03d.%03d.%03d', split /\D+/, shift;
    my $y = sprintf '%03d.%03d.%03d', split /\D+/, shift;
    return $x cmp $y;
}
