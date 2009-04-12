#-*- perl -*-

package Unicode::LineBreak;
require 5.008;

=head1 NAME

Unicode::LineBreak - UAX #14 Unicode Line Breaking Algorithm

=head1 SYNOPSIS

    use Unicode::LineBreak;
    $lb = Unicode::LineBreak->new($string);
    $string = $lb->break;

=head1 DESCRIPTION

Unicode::LineBreak performs Line Breaking Algorithm described in
Unicode Standards Annex #14 [UAX #14].  East_Asian_Width informative
properties [UAX #11] will be concerned to determin breaking points.

=cut

### Pragmas:
use strict;
use vars qw($VERSION @EXPORT_OK @ISA $Config);

### Exporting:
use Exporter;

### Inheritance:
@ISA = qw(Exporter);

### Other modules:
use Carp qw(croak carp);
use Encode;
use MIME::Charset qw(:info);

### Globals

### The package version, both in 1.23 style *and* usable by MakeMaker:
$VERSION = '0.001_01';

### Public Configuration Attributes
$Config = {
    %{$MIME::Charset::Config}, # Detect7bit, Replacement, Mapping
    Charset => 'UTF-8',
    Context => '',
    HangulAsAL => 'NO',
    Language => 'XX',
    MaxColumns => 76,
    NSKanaAsID => 'NO',
    OutputCharset => 'UTF-8',
};
eval { require Unicode::LineBreak::Defaults; };

### Constants
use constant MANDATORY => 2;
use constant ALLOWED => 1;
use constant NO_BREAK => 0;
use constant EOT => -1;

### Privates
require Unicode::LineBreak::Data;
require Unicode::LineBreak::Rules;
sub lb_null { "" }

my @ALL_CLASSES = qw(BK CR LF CM NL SG WJ ZW GL SP B2 BA BB HY CB CL EX IN NS OP QU IS NU PO PR SY AI AL H2 H3 ID JL JV JT SA XX);  

my $EASTASIAN_CHARSETS = qr{
    ^BIG5 |
    ^CP9\d\d |
    ^EUC- |
    ^GB18030 | ^GB2312 | ^GBK |
    ^HZ |
    ^ISO-2022- |
    ^KS_C_5601 |
    ^SHIFT_JIS
}ix;

my $EASTASIAN_LANGUAGES = qr{
    ^AIN |
    ^JA\b | ^JPN |
    ^KO\b | ^KOR |
    ^ZH\b | ^CHI
}ix;


=head1 PUBLIC INTERFACE

=over 4

=item new [STRING, [OPTIONS...]]

DeScRiPtIoNs...

=back

=cut

sub new {
    my $class = shift;
    my $str = shift;

    my $self = { _pos => 0 };
    &config($self, @_);
    if (Encode::is_utf8($str)) {
	$self->{_str} = $str;
    } else {
	$self->{_str} = $self->{_charset}->decode($str);
    }
    bless $self, $class;
}

=over 4

=item config [OPTIONS...]

=over 4

=item Charset => CHARSET

=item Context => C<"EASTASIAN"> | C<"NONEASTASIAN">

=item Language => LANGUAGE

DeScRiPtIoNs...

=item HangulAsAL => C<"YES"> | C<"NO">

Treat hangul syllables and conjoining jamos as AL.

=item MaxColumns => NUMBER

DeScRiPtIoNs...

=item NSKanaAsID => C<"YES"> | C<"NO">

Treat hiragana/katakana non-starters and prolonged signs (NS) as ID.
This feature is optional in [JIS X 4051].

=item OutputCharset => CHARSET

DeScRiPtIoNs...

=back

=back

=cut

sub config {
    my $self = shift;
    my %params = @_;

    ## Get Options.

    # Character set and language assumed.
    my $charset = uc($params{Charset} || $Config->{Charset});
    $self->{_charset} = MIME::Charset->new($charset);
    my $ocharset = uc($params{OutputCharset} || $charset);
    $self->{_output_charset} = $ocharset;
    if ($ocharset ne '_UNICODE_') {
	$self->{_charset}->encoder(MIME::Charset->new($ocharset));
    }
    $self->{_language} = uc($params{Language} || $Config->{Language});
    $self->{_language} =~ s/_/-/g;
    $self->{_max_columns} = $params{MaxColumns} || $Config->{MaxColumns};

    # Context. Either East Asian or Non-East Asian.
    my $context = uc($params{Context} || $Config->{Context});
    if ($context =~ /^(N(ON)?)?EA(STASIAN)?/) {
	if ($context =~ /^N/) {
	    $context = 'NONEASTASIAN';
	} else {
	    $context = 'EASTASIAN';
	}
    } elsif ($self->{_charset}->as_string =~ /$EASTASIAN_CHARSETS/) {
        $context = 'EASTASIAN';
    } elsif ($self->{_language} =~ /$EASTASIAN_LANGUAGES/) {
	$context = 'EASTASIAN';
    } else {
	$context = 'NONEASTASIAN';
    }
    $self->{_context} = $context;

    # Some flags
    my $nskanaasid = uc($params{NSKanaAsID} || $Config->{NSKanaAsID});
    my $hangulasal = uc($params{HangulAsAL} || $Config->{HangulAsAL});

    ## Customize Line Breaking Classes.

    my %lb;
    foreach my $c (@ALL_CLASSES) {
	$lb{$c} = [$c];
    }

    # Resolve SA, SG and XX: See UAX #14 6.1 LB1.
    push @{$lb{CM}}, 'SAcm';
    push @{$lb{AL}}, qw(SA SG XX);

    # Resolve AI.
    if ($context eq 'EASTASIAN') {
	push @{$lb{ID}}, 'AI';
    } else {
	push @{$lb{AL}}, 'AI';
    }

    # Options for katakana/hiragana NS: See [JIS X 4051] 6.1.1 note 8.
    if ($nskanaasid eq 'YES') {
	push @{$lb{ID}}, 'NSid';
    } else {
	push @{$lb{NS}}, 'NSid';
    }

    # Options for hangul syllables and conjoining jamos: See [UAX #14] 5.1.
    if ($hangulasal eq 'YES') {
	foreach my $c (qw(H2 H3 JL JT JV)) {
	    push @{$lb{AL}}, $c;
	    $lb{$c} = [qw(null)];
	}
    }

    foreach my $c (keys %lb) {
	$self->{"lb_$c"} = '(?:' .
	    (join '|', map qr{\p{lb_$_}}, @{$lb{$c}}) .
	    ')';
    }

    ## Customize East Asian Widths.

    $self->{"ea_z"} ||= qr{\p{ea_z}};
    if ($context eq 'EASTASIAN') {
	$self->{"ea_w"} ||= qr{(?:\p{ea_F}|\p{ea_W}|\p{ea_A})};
	$self->{"ea_n"} ||= qr{(?:\p{ea_H}|\p{ea_Na}|\p{ea_N})};
    } else {
	$self->{"ea_w"} ||= qr{(?:\p{ea_F}|\p{ea_W})};
	$self->{"ea_n"} ||= qr{(?:\p{ea_H}|\p{ea_Na}|\p{ea_A}|\p{ea_N})};
    }

    return $self;
}

=over 4

=item break

DeScRiPtIoNs...

=back

=cut

sub break {
    my $self = shift;
    my ($action, $sym);
    my $result = '';
    my $bbuf = '';
    my $blen = 0;
    my $pbuf = '';
    my $plen = 0;

    $self->{_pos} = 0;
    while (1) {
	($action, $sym) = $self->_breakable;
	$sym =~ s/\u0020*$//;
	my $sp = $& || '';

	if ($bbuf ne '' and
	    $self->{_max_columns} < $blen + $plen + $self->_strwidth($sym)) {
	    $result .= $bbuf."\n";
	    $bbuf = '';
	    $blen = 0;
	    $pbuf .= $sym.$sp;
	    $plen += $self->_strwidth($sym.$sp);
	} else {
	    $pbuf .= $sym.$sp;
	    $plen += $self->_strwidth($sym.$sp);
	}

	if ($action == EOT) {
	    $result .= $bbuf.$pbuf;
	    last;
	} elsif ($action == MANDATORY) {
	    $result .= $bbuf.$pbuf;
	    $bbuf = $pbuf = '';
	    $blen = $plen = 0;
	} elsif ($action == ALLOWED) {
	    $bbuf .= $pbuf;
	    $blen += $plen;
	    $pbuf = '';
	    $plen = 0;
	}
    }

    if ($self->{_output_charset} eq '_UNICODE_') {
	return $result;
    } else {
	return $self->{_charset}->encode($result);
    }
}

sub _strwidth {
    my $self = shift;
    my $str = shift;
    my $result = 0;

    return 0 unless defined $str and length $str;
    my $i;
    for ($i = 0; $i < length $str; $i++) {
	$result += $self->_charwidth(substr($str, $i, 1));
    }
    return $result;
}

sub _charwidth {
    my $self = shift;
    my $char = shift;

    return 0 unless defined $char and length $char;
    croak sprintf "Not a single character: ``\\x%*v02X''", '\\x', $char
	unless length($char) == 1;

    if ($char =~ /$self->{ea_z}/) {
	return 0;
    } elsif ($char =~ /$self->{ea_w}/) {
	return 2;
    } else {
	return 1;
    }
}

=head2 Configuration Files

Built-in defaults of option parameters for L<"new"> and
L<"config"> can be overridden by configuration files:
F<MIME/Charset/Defaults.pm> and F<Unicode/LineBreak/Defaults.pm>.
For more details read F<Unicode/LineBreak/Defaults.pm.sample>.

=head2 Conformance to Standards

Character properties based on by this module are defined by
Unicode Standards version 5.1.0.

This module implements UAX14-C2.

=over 4

=item *

Hiragana/katakana small letters and prolonged signs may be treated as
either NS or ID by choice (See [JIS X 4051] 6.1.1).

=item *

Hangul syllables and conjoining jamos may be treated as
either H2/H3/JL/JT/JV or AL by choice.

=item *

Characters assigned to AI may be resolved to either AL or ID by choice.

=item *

Character(s) assigned to CB are not resolved.

=item *

Characters assigned to SA are resolved to AL,
except that characters that have General_Category Mn or Mc be resolved to CM.

=item *

Characters assigned to SG or XX are resolved to AL.

=back

=head1 BUGS

B<Slightly slow>.  XS implementation might be required.

=head1 VERSION

This is pre-alpha release.

Development versions of this module may be found at 
L<http://hatuka.nezumi.nu/repos/Unicode-LineBreak/>.

=head1 SEE ALSO

L<Text::Wrap>.

=head1 REFERENCES

=over 4

=item [JIS X 4051]

JIS X 4051:2004
I<日本語文書の組版方法> (I<Formatting Rules for Japanese Documents>),
published by Japanese Standards Association, 2004.

=begin comment

=item [JLREQ]

Y. Anan, H. Chiba, J. Edamoto et al (2008).
I<Requirements of Japanese Text Layout: W3C Working Draft 15 October 2008>.
L<http://www.w3.org/TR/2008/WD-jlreq-20081015/>.

=end comment

=item [UAX #11]

A. Freytag (2008).
I<Unicode Standard Annex #11: East Asian Width>, Revision 17.
L<http://unicode.org/reports/tr11/>.

=item [UAX #14]

A. Freytag and A. Heninger (2008).
I<Unicode Standard Annex #14: Unicode Line Breaking Algorithm>, Revision 22.
L<http://unicode.org/reports/tr14/>.

=back

=head1 AUTHORS

Copyright (C) 2009 Hatuka*nezumi - IKEDA Soji <hatuka(at)nezumi.nu>.

This program is free software; you can redistribute it and/or modify it 
under the same terms as Perl itself.

=cut

1;
