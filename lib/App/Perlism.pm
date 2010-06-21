package App::Perlism;
use Moose;
use Cache::Memcached::Fast;
use Digest::MD5 qw(md5_hex);
use Encode;
use Net::Twitter;
use namespace::autoclean;

with 'MooseX::Getopt', 'MooseX::SimpleConfig';

has consumer_key => ( is => 'rw', isa => 'Str', required => 1 );
has consumer_secret => ( is => 'rw', isa => 'Str', required => 1 );
has access_token => ( is => 'rw', isa => 'Str', required => 1 );
has access_token_secret => ( is => 'rw', isa => 'Str', required => 1 );
has ignore_users => ( is => 'rw', isa => 'ArrayRef' );
has ignore_users_re => ( is => 'rw', isa => 'Maybe[RegexpRef]', lazy_build => 1);
has ignore_text => ( is => 'rw', isa => 'ArrayRef' );
has ignore_text_re => (is => 'rw', isa => 'Maybe[RegexpRef]', lazy_build => 1);
has keywords => ( is => 'rw', isa => 'ArrayRef', required => 1, default => sub { +[ "anyevent", "moose", "perl", "perlism", "plack", "psgi" ] } );
has query => ( is => 'rw', isa => 'Str', lazy_build => 1);
has client => (
    is => 'ro',
    isa => 'Net::Twitter',
    lazy_build => 1,
);

sub _build_client {
    my $self = shift;
    my $client = Net::Twitter->new(
        traits => [ qw(API::REST API::Search OAuth) ],
        consumer_key => $self->consumer_key,
        consumer_secret => $self->consumer_secret,
        source => "perlism",
        ssl => 1,
    );
    $client->access_token( $self->access_token );
    $client->access_token_secret( $self->access_token_secret );

    return $client;
}

sub _build_ignore_text_re {
    my $self = shift;
    my $ignore_text = $self->ignore_text or return ();

    my $x = join( '|', @$ignore_text );
    return qr/$x/;
}

sub _build_ignore_users_re {
    my $self = shift;
    my $ignore_users = $self->ignore_users or return ();

    my $x = join( '|', @$ignore_users );
    return qr/$x/;
}

sub _build_query {
    my $self = shift;
    return join( ' OR ', @{ $self->keywords } );
}

sub run {
    my $self = shift;

    my $client = $self->client();
    my $cache = Cache::Memcached::Fast->new({
        servers => [ 'localhost:11211' ],
        namespace => 'perlism:'
    });
    my $query = $self->query;
    my $ignore_users_re = $self->ignore_users_re;
    my $ignore_text_re = $self->ignore_text_re;
    my @langs = ('', 'ja');
    foreach my $lang (@langs) {
        my $result = $client->search({ q => $query, lang => $lang, rpp => 100 });
        foreach my $status ( @{$result->{results}} ) {
            next if $cache->get( "id.$status->{id}" );
            next if $ignore_users_re && $status->{from_user} =~ /$ignore_users_re/;
            # only allow JP
            next if $status->{text} !~ /\p{InJapanese}/;

            # if it looks like a ping-pong to perlism itself,
            # don't RT it
            next if $status->{text} =~ /[@!]perlism/;
            next if $ignore_text_re && $status->{text} =~ /$ignore_text_re/;


            my $message = sprintf("RT !%s: %s", $status->{from_user}, $status->{text} );
            if (length $message > 140) {
                substr($message, 137, length($message) - 137, '...');
            }
            $message =~ s/@/!/g;
            my $sig = md5_hex( encode_utf8 $message );
            next if $cache->get( "sig.$sig" );
            $client->update( $message );
            $cache->set( "id.$status->{id}" );
            $cache->set( "sig.$sig" );
        }
    }
}

sub InJapanese {
    return <<'EOM';
+utf8::InHiragana
+utf8::InKatakana
+utf8::InCJKUnifiedIdeographs
+utf8::InCJKSymbolsAndPunctuation
+utf8::InHalfwidthAndFullwidthForms
EOM
}

__PACKAGE__->meta->make_immutable();

1;