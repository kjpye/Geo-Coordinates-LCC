NAME
====

Geo::Coordinates::LCC - Raku module for converting coordinates between latitude and logitude, and coordinates in a Lambert Conformal Conic projection.

SYNOPSIS
========

    use Geo::Coordinates::LCC;

    set-ellipse 'WGS-84';
    set-projection 'vicgrid94';
    my ($easting,$northing)=|latlon-to-lcc($latitude,$longitude);

    my ($latitude,$longitude)=|utm-to-latlon($easting,$northing);

    my @projections = projection-names;

    my %info = projection-info 'vicgrid94';
    dd %info;

DESCRIPTION
===========

This module will translate latitude/longitude coordinates to Lambert Conformal Conic (LCC) coordinates and vice versa.

Lambert Conformal Conic Projection
----------------------------------

The [Lambert Conformal Conic projection](https://en.wikipedia.org/wiki/Lambert_conformal_conic_projection) is a map projection based on projecting the surface of the earth onto a cone. It is often used for mapping areas which extend significantly in an east-west direction in mid-latitudes. It is often used for maps in the United States and Australia for example.

A practical Lambert Conformal Conical projection requires seven parameters to define it:

  * two standard latitudes (φ₁ and φ₂)—these define where the cone touches the earth;

  * an origin latitude (φ₀) which specifies the zero for the northings;

  * an origin longitude (λ₀) which defines the zero for the eastings;

  * a false easting and a flase northing to ensure coordinatges are positive; and

  * a reference ellipsoid

The equations used in this module are from "Map Projections - A Working Manual" by John P. Snyder. (https://pubs.usgs.gov/pp/1395/report.pdf)

USAGE
-----

    my $geometry = Geo::Geometry::PolygonZ.new(...); # latitude and longitude
    set-projection 'nswgrid';
    my $map-points = latlon-to-lcc $geometry;
    # $map-points contains Geo::Geometry::Polygon object with eastings and northings

or

    my $geometry = Geo::Geometry::PolygonZ.new(...); # eastings and northings
    set-projection 'nswgrid';
    my $map-points = lcc-to-latlon $geometry;
    # $map-points contains Geo::Geometry::Polygon object with latitude and longitude

Before you can convert between latitude/longitude and easting/northing, you need to specify the specifics of the projection. The module knows about a few projections, so you can either use those projections specifically, or you can specify the details yourself.

The following projections are predefined:

  * US

  * VicGrid

  * VicGrid94

  * NSWGrid94

You can see the parameters using the functions below. (Suggestions for additional projections are welcome.)

### projection-names

    my $names = projection-names();
    .say for $names;

Returns an array of strings containing the names of the available pre-defined projections.

### projection-info

    my %info = projection-info('vicgrid94');
    dd %info;

Returns a hash with the details of the projection.

### set-projection

    set-projection('vicgrid94');

or

    set-projection(φ1, φ2, φ0, λ0, $falqse-easting, $falsenorthing, $ellipsoid);

Specifies the projection to be used. This must be called before either latlon-to-lcc or lcc-to-latlon. The final argument to the second version is the name of an ellipsoid from Geo::Ellipsoids.

### latlon-to-lcc and lcc-to-latlon

Each of these routines can take any Geo::Geometry object, and will return a similar object, except that any object with Z and/or M components will have those components removed. For example, if you pass a LineStringZ object to these routines, the return object will be a LineString object.

In addition you can pass `latlon-to-lcc` the raw latitude and longitude in degrees. The return value in this case will be a list containg the easting and northing. You can also pass `lcc-to-latlon` an easting and a northing (in metres) and the returned value will a list containing the latitude and longitude in degrees.

BUGS
====

This module is not thread-safe. `set-projection` pre-calculates some of the values needed by `latlon-to-lcc` and `lcc-to-latlon`. If you call set-projection in separate threads, including using `hyper` and `race`, then the results might be interesting. If you call set-projection once, and then use multiple threads using the same projection, you might be safe. There are no other global variables used apart from those used to cache projection information.

AUTHOR
======

Kevin Pye, kjpraku@pye.id.au

COPYRIGHT
=========

Copyright ⓒ 2022 by Kevin Pye.

This package is free software; you can redistribute it and/or modify it under the same terms as Raku itself. 

