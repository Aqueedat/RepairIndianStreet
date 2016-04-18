package FixMyStreet::Cobrand::UKCouncils;
use base 'FixMyStreet::Cobrand::UK';

# XXX Things using this cobrand base assume that a body ID === MapIt area ID

use strict;
use warnings;

use Carp;
use URI::Escape;

sub is_council {
    1;
}

sub path_to_web_templates {
    my $self = shift;
    return [
        FixMyStreet->path_to( 'templates/web', $self->moniker )->stringify,
        FixMyStreet->path_to( 'templates/web/fixmystreet-uk-councils' )->stringify,
        FixMyStreet->path_to( 'templates/web/fixmystreet' )->stringify
    ];
}

sub site_key {
    my $self = shift;
    return $self->council_url;
}

sub restriction {
    return { cobrand => shift->moniker };
}

sub updates_restriction {
    my ($self, $rs) = @_;
    return $rs->to_body($self->council_id);
}

sub admin_problems_restriction {
    my ($self, $rs) = @_;
    return $rs->to_body($self->council_id);
}

sub base_url {
    my $self = shift;
    my $base_url = FixMyStreet->config('BASE_URL');
    my $u = $self->council_url;
    if ( $base_url !~ /$u/ ) {
        # council cobrands are not https so transform to http as well
        $base_url =~ s{(https?)://(?!www\.)}{http://$u.}g;
        $base_url =~ s{(https?)://www\.}{http://$u.}g;
    }
    return $base_url;
}

sub enter_postcode_text {
    my ($self) = @_;
    return 'Enter a ' . $self->council_area . ' postcode, or street name and area';
}

sub area_check {
    my ( $self, $params, $context ) = @_;

    my $councils = $params->{all_areas};
    my $council_match = defined $councils->{$self->council_id};
    if ($council_match) {
        return 1;
    }
    my $url = 'https://www.fixmystreet.com/';
    if ($context eq 'alert') {
        $url .= 'alert';
    } else {
        $url .= 'around';
    }
    $url .= '?pc=' . URI::Escape::uri_escape( $self->{c}->get_param('pc') )
      if $self->{c}->get_param('pc');
    $url .= '?latitude=' . URI::Escape::uri_escape( $self->{c}->get_param('latitude') )
         .  '&amp;longitude=' . URI::Escape::uri_escape( $self->{c}->get_param('longitude') )
      if $self->{c}->get_param('latitude');
    my $error_msg = "That location is not covered by " . $self->council_name . ".
Please visit <a href=\"$url\">the main FixMyStreet site</a>.";
    return ( 0, $error_msg );
}

# All reports page only has the one council.
sub all_reports_single_body {
    my $self = shift;
    return { name => $self->council_name };
}

sub reports_body_check {
    my ( $self, $c, $code ) = @_;

    # We want to make sure we're only on our page.
    unless ( $self->council_name =~ /^\Q$code\E/ ) {
        $c->res->redirect( 'https://www.fixmystreet.com' . $c->req->uri->path_query, 301 );
        $c->detach();
    }

    return;
}

sub recent_photos {
    my ( $self, $area, $num, $lat, $lon, $dist ) = @_;
    $num = 2 if $num == 3;
    return $self->problems->to_body($self->council_id)->recent_photos( $num, $lat, $lon, $dist );
}

sub front_stats_data {
    my ( $self ) = @_;

    my $recency         = '1 week';
    my $shorter_recency = '3 days';

    my $fixed   = $self->problems->to_body($self->council_id)->recent_fixed();
    my $updates = $self->problems->to_body($self->council_id)->number_comments();
    my $new     = $self->problems->to_body($self->council_id)->recent_new( $recency );

    if ( $new > $fixed && $self->shorten_recency_if_new_greater_than_fixed ) {
        $recency = $shorter_recency;
        $new     = $self->problems->to_body($self->council_id)->recent_new( $recency );
    }

    my $stats = {
        fixed   => $fixed,
        updates => $updates,
        new     => $new,
        recency => $recency,
    };

    return $stats;
}


# Returns true if the cobrand owns the problem.
sub owns_problem {
    my ($self, $report) = @_;
    my @bodies;
    if (ref $report eq 'HASH') {
        return unless $report->{bodies_str};
        @bodies = split /,/, $report->{bodies_str};
        @bodies = FixMyStreet::DB->resultset('Body')->search({ id => \@bodies })->all;
    } else { # Object
        @bodies = values %{$report->bodies};
    }
    my %areas = map { %{$_->areas} } @bodies;
    return $areas{$self->council_id} ? 1 : undef;
}

# If the council is two-tier then show pins for the other council as grey
sub pin_colour {
    my ( $self, $p, $context ) = @_;
    return 'grey' if $self->is_two_tier && !$self->owns_problem( $p );
    return $self->next::method($p, $context);
}

# If we ever link to a county problem report, needs to be to main FixMyStreet
sub base_url_for_report {
    my ( $self, $report ) = @_;
    if ( $self->is_two_tier ) {
        if ( $self->owns_problem( $report ) ) {
            return $self->base_url;
        } else {
            return FixMyStreet->config('BASE_URL');
        }
    } else {
        return $self->base_url;
    }
}

1;
