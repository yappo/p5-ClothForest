package CloudForecast::Component::ClothForest;
use strict;
use warnings;
use CloudForecast::Component -connector;

use JSON;
use LWP::UserAgent;
my $UA = LWP::UserAgent->new( agent => 'CloudForecast::Component::ClothForest/0.01' );

sub get {
    my $self = shift;
    use Data::Dumper;warn Dumper($self);
    my $host = $self->config->{url};
    my($section, $service) = split '\.', $self->address;
    my $graph = $self->args->[0];
    my $res  = $UA->get("${host}api/$service/$section/$graph/");
    return unless $res->is_success;
    decode_json $res->content;
}

1;

