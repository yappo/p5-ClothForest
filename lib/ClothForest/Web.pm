package ClothForest::Web;
use strict;
use warnings;
use Shirahata -base;
use ClothForest::DB;
use CloudForecast::ConfigLoader;
use CloudForecast::Log;
use List::Util;
use Plack::Builder;
use Plack::Loader;
use Net::IP;
use Path::Class;
use JSON;

accessor(qw/configloader root_dir global_config server_list port host allowfrom front_proxy data_dir host_config_dir db/);

sub run {
    my $self = shift;

    my $configloader = CloudForecast::ConfigLoader->new({
        root_dir => $self->root_dir,
        global_config => $self->global_config,
        server_list => $self->server_list,
    });
    $configloader->load_all();

    $self->configloader($configloader);
    $self->data_dir( dir $configloader->{global_config}{data_dir} );
    $self->host_config_dir( dir $configloader->{global_config}{host_config_dir} );
    die 'data_dir is not found: ' . $self->data_dir unless -d $self->data_dir;
    die 'host_config_dir is not found: ' . $self->data_dir unless -d $self->host_config_dir;

    $self->db( ClothForest::DB->new( $self->data_dir ) );

    my $allowfrom = $self->allowfrom || [];
    my $front_proxy = $self->front_proxy || [];

    my @frontproxies;
    foreach my $ip ( @$front_proxy ) {
        my $netip = Net::IP->new($ip)
            or die "not supported type of rule argument [$ip] or bad ip: " . Net::IP::Error();
        push @frontproxies, $netip;
    }

    my $app = $self->psgi;
    $app = builder {
        enable 'Plack::Middleware::Lint';
        enable 'Plack::Middleware::StackTrace';
        if ( @frontproxies ) {
            enable_if {
                my $addr = $_[0]->{REMOTE_ADDR};
                my $netip;
                if ( defined $addr && ($netip = Net::IP->new($addr)) ) {
                    for my $proxy ( @frontproxies ) {
                       my $overlaps = $proxy->overlaps($netip);
                       if ( $overlaps == $IP_B_IN_A_OVERLAP || $overlaps == $IP_IDENTICAL ) {
                           return 1;
                       } 
                    }
                }
                return;
            } "Plack::Middleware::ReverseProxy";
        }
        if ( @$allowfrom ) {
            my @rule;
            for ( @$allowfrom ) {
                push @rule, 'allow', $_;
            }
            push @rule, 'deny', 'all';
            enable 'Plack::Middleware::Access', rules => \@rule;
        }
        enable 'Plack::Middleware::Static',
            path => qr{^/(favicon\.ico$|static/)},
            root => Path::Class::dir($self->root_dir, 'htdocs')->stringify;
        $app;
    };

    my $loader = Plack::Loader->load(
        'Starlet',
        port => $self->port || 5500,
        host => $self->host || 0,
        max_workers => 2,
    );
    $loader->run($app);
}

get '/' => sub {
    my ( $self, $c ) = @_;
    $c->render(
        'index',
        cloudforecast_url => $self->configloader->global_component_config->{ClothForest}{cloudforecast_url},
    );
};

get '/api/{service:[0-9A-Za-z_-]+}/{section:[0-9A-Za-z_-]+}/{graph:[0-9A-Za-z_-]+}/' => sub {
    my ( $self, $c ) = @_;
    my $data = $self->db->get($c->{args}{service}, $c->{args}{section}, $c->{args}{graph});
    unless ($data) {
        return $c->not_found;
    }

    $c->res->status( 200 );
    $c->res->content_type('application/json; charset=UTF-8');
    $c->res->body( encode_json($data) );
    $c->res;
};

post '/api/{service:[0-9A-Za-z_-]+}/{section:[0-9A-Za-z_-]+}/{graph:[0-9A-Za-z_-]+}/' => sub {
    my ( $self, $c ) = @_;

    unless ($c->req->param('number')) {
        $c->res->status( 403 );
        $c->res->content_type('text/html; charset=UTF-8');
        $c->res->body( 'please number param' );
        return $c->res;
    }

    my $is_new = $self->db->update(
        $c->{args}{service}, $c->{args}{section}, $c->{args}{graph}, $c->req->param('number'), $c->req->param('description'),
        { mode => $c->req->param('mode') }
    );
    if ($is_new) {
        eval {
            # config update
            my $configs = $self->db->create_config;
            my $server_list = file($self->server_list);
            open my $fh, '>', $server_list or die "global_config open error";
            print $fh $configs->{server};
            close $fh;

            for my $file (keys %{ $configs->{sections} }) {
                my $path = $self->host_config_dir->file($file);
                $path->dir->mkpath;
                open my $fh, '>', $path or die "host config $file open error";
                print $fh $configs->{sections}{$file};
                close $fh;
            }
        };
        $@ and CloudForecast::Log->warn($@);
    }

    $c->res->status( 200 );
    $c->res->content_type('text/html; charset=UTF-8');
    $c->res->body( 'ok' );
    $c->res;
};

1;

__DATA__
@@ base
<html>
<head>
<link rel="stylesheet" type="text/css" href="<: $c.req.uri_for('/static/bootstrap.min.css') :>" />
<title><: block title -> {} :> ClothForest</title>
</head>
<body>

<div id="header">
<h1 class="title"><a href="<: $c.req.uri_for('/') :>">ClothForest</a></h1>
<div class="welcome">
<ul>
<li><a href="<: $c.req.uri_for('/') :>">TOP</a></li>
</ul>
</div>
<div id="headmenu">
: block headmenu -> {
&nbsp;
: }
</div>

<h2 id="ptitle">
: block ptitle -> {
<a href="<: $c.req.uri_for('/') :>">TOP</a>
: }
</h2>

</div>
<div id="headspacer"></div>

<div id="content">

: block content -> { }

</div>

</body>
</html>

@@ index
: cascade 'base'
: around title -> {
TOP « 
: }

: around headmenu -> {
: }

: around content -> {
<h3>info</h3>
<p>
    ClothForest は、グラフの数値を Web API で登録する為の CloudForecast のラッパーです。<br />
    サービス名、グラフのカテゴリ、グラフの名前を [A-Za-z0-9_-] の範囲でそれぞれ決めてから HTTP POST する事で、自動的にグラフ生成を行います。<br />
    <a href="https://github.com/yappo/p5-ClothForest/" target="_blank">https://github.com/yappo/p5-ClothForest/</a> にて開発中です。<br />
    利用するには CloudForecast と Makefile.PL 内に記載してある依存モジュールを入れてください。<br />
    net-snmp は不要です。<br />
</p>

<ul>
    <li><a href="<: $cloudforecast_url :>" target="_blank"><: $cloudforecast_url :> (連動している CloudForecast)</a></li>
</ul>

<h3>usage</h3>

<h4>グラフの登録方法</h4>

<p>
以下の URL を POST メソッドで叩いてください。<br />
<pre><: $c.req.uri_for('/api/:service_name/:section_name/:graph_name/') :></pre>
ClothForest では、多数のサービスで利用可能な共通 Web Graph API を目標として作られています。 URL 中の各名前に関しては下の表を参考にしてください。<br />
<table>
    <tr>
      <th>例中の名前</th>
      <th>役割</th>
      <th>具体例を , 区切りで</th>
    </tr>
    <tr>
      <td>:service_name</td>
      <td>グラフを取りたいサービスの名前</td>
      <td>hatenablog, ficia, loctouch, ninjyatoriai</td>
    </tr>
    <tr>
      <td>:section_name</td>
      <td>そのサービスの中での、グラフを取る対象が属してる機能やシステム名</td>
      <td>entry, user, spot, items</td>
    </tr>
    <tr>
      <td>:graph_name</td>
      <td>具体的に何のグラフか</td>
      <td>total_entry, kakin_user, muryo_user, syuriken_no_ureta_kazu</td>
    </tr>
</table><br />

もし、忍者取り合いっていうサービスのアイテムの中の手裏剣が売りたい数だったら
<pre><: $c.req.uri_for('/api/ninjyatoriai/items/syuriken_no_ureta_kazu/') :></pre>
に対して POST します。
</p>

<p>また、 POST する時には以下のパラメータをつけます。<br />
<table>
    <tr>
      <td>number</td>
      <td>グラフに与える数値</td>
      <td>必須</td>
    </tr>
    <tr>
      <td>description</td>
      <td>グラフの説明を簡潔に入れます</td>
      <td>オプション</td>
    </tr>
    <tr>
      <td>mode</td>
      <td>登録済みの数値を number の値で加算する時には mode=count とします。<br />通常は number の数値で常に上書きます。</td>
      <td>オプション</td>
    </tr>
</table><br />

LWP::UserAgent を使うと以下の用になります。<br />
<pre>my $ua = LWP::UserAgent->new;
$ua->post('<: $c.req.uri_for('/api/ninjyatoriai/items/syuriken_no_ureta_kazu/') :>', {
    number      => 10,
    description => '説明文',
});</pre><br />

curl を使うと以下の用になります。<br />
<pre>$ curl -F number=10 -F description=説明文 <: $c.req.uri_for('/api/ninjyatoriai/items/syuriken_no_ureta_kazu/') :></pre><br />

現在のところ一種類のグラフしか描けませんが、この辺はそのうちいい感じになる予定です。<br />
</p>

<h3>setup</h3>

<p>
    はじめに、既存の CloudForecast 環境とは共存は不可能なので、以下に説明する ClothForest 用の設定ファイルを作ってから動かします。<br />
    当然ながら CloudForecast と同じサーバで動かします。<br />
</p>
<p>
    cloudforecast.yaml は以下の用に指定します。<br />
    <pre>---
config:
  data_dir: 絶対パスで記述する
  host_config_dir: 絶対パスで記述する
component_config:
  ClothForest
    url: http://127.0.0.1:5500/ # ClothForest の URL を入れる (動いてるサーバからアクセス出来る URL )
    cloudforecast_url: http://cloudforecast.example.com/ # CloudForecast の URL を入れる (ユーザが見れる URL)
</pre>

    あとで ClothForest により自動的に書き換えられますが server_list.yaml を以下の用にします。<br />
    <pre>--- #tmp
servers:
</pre><br />

    用意ができたら clothforest_web を起動します。<br />
    <pre>$ clothforest_web -c cloudforecast.yaml -l server_list.yaml -p 5500</pre><br />
    オプションは cloudforecast_web に準拠しています。<br />
    この例だと 5500 番ポートでサーバが立ち上がってるので、ブラウザからアクセスすればこのマニュアルが表示されます。<br />
    <br />
    最後に重要ですが CloudForecast のプロセス一式も立ち上げます。頻繁に再起動が行われる事が予想されるので -r オプションが必須です。<br />
    <pre>$ cloudforecast_radar -c cloudforecast.yaml -l server_list.yaml -r
$ cloudforecast_web -c cloudforecast.yaml -l server_list.yaml -r -p 5000</pre><br />
<br />
    以上で ClothForest が使えるようになってる筈ですので、どうぞご利用ください。
</p>

: } # content

