package CloudForecast::Data::Clothforest::Basic;
use strict;
use warnings;
use parent 'CloudForecast::Data::Clothforest::Base';

use CloudForecast::Data -base;

rrds   'number' => 'GAUGE';
graphs 'number' => 'number';

title {
    my $c = shift;
    $c->args->[0];
};

sysinfo {
    my $c = shift;
    $c->ledge_get('sysinfo') || [];
};

fetcher {
    my $c = shift;
    my $clothforest = $c->component('ClothForest');
    my $data = $clothforest->get;
    die 'can not get clothforest' unless $data;
    $c->ledge_set( 'sysinfo', [
        current    => $data->{number},
        created_at => $data->{created_at},
        updated_at => $data->{updated_at},
    ] );
    [ $data->{number} ];
};


1;
__DATA__
@@ number
DEF:my1=<%RRD%>:number:AVERAGE
AREA:my1#eaaf00:Number
GPRINT:my1:LAST:Cur\: %.0lf
GPRINT:my1:AVERAGE:Ave\: %.0lf
GPRINT:my1:MAX:Max\: %.0lf
GPRINT:my1:MIN:Min\: %.0lf
