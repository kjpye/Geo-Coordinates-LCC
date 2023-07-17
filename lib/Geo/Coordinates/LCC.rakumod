unit module Geo::Coordinates::LCC;

use Geo::Geometry;
use Geo::Ellipsoids;

# more accurate than π ÷ 180
constant \deg2rad = Rat.new(66627445592888887, 180 × 21208174623389167);
constant \rad2deg = Rat.new(180 × 21208174623389167, 66627445592888887);

sub postfix:<°> { $^a × deg2rad }
sub prefix:<ln>($a) { log $a; }

class Projection {
  has $.name;
  has $.lat1;
  has $.lat2;
  has $.lat0;
  has $.long0;
  has $.false-easting;
  has $.false-northing;
  has $.ellipsoid;

  method create($name, $lat1, $lat2, $lat0, $long0, $false-easting, $false-northing, $ellipsoid?) {
    $ellipsoid //= '';
    Projection.new(:$name, :$lat1, :$lat2, :$lat0, :$long0, :$false-easting, :$false-northing, :$ellipsoid);
  }
}

my @Projection;
my %Projection;

our sub cleanup-projection-name(Str $copy is copy) is export {
  $copy .= lc;
  $copy ~~ s:g/ \( <-[)]>* \) //;   # remove text between parentheses
  $copy ~~ s:g/ <[\s-]> //;         # no blanks or dashes
  $copy;
}

BEGIN {

  @Projection = (
      Projection.create('us',         33°,     45°,     23°,    -96°,       0,       0, 'Clarke 1866'),
      Projection.create('vicgrid',   -36°,    -38°,    -37°,    145°, 2500000, 4500000, 'Australian National'), # AGD66
      Projection.create('vicgrid94', -36°,    -38°,    -37°,    145°, 2500000, 2500000, 'WGS-84'), # GDA94
      Projection.create('nswgrid94', -30.75°, -35.45°, -33.25°, 147°, 9300000, 4500000, 'WGS-94'), # GDA94
  );
  for @Projection -> $pr {
      %Projection{$pr.name} = $pr;
      %Projection{cleanup-projection-name $pr.name} = $pr;
  }

}

# Returns all pre-defined projection names
sub projection-names() is export {
  @Projection ==> map { .name };
}

# Returns "official" name, ...
#FIX
# Examples:   my($name, $r, $sqecc) = projection-info 'wgs84';
#             my($name, $r, $sqecc) = projection-info 'WGS 84';
#             my($name, $r, $sqecc) = projection-info 'WGS-84';
#             my($name, $r, $sqecc) = projection-info 'WGS-84 (new specs)';
#             my($name, $r, $sqecc) = projection-info 22;

sub projection-info(Str $id) is export {
  %Projection{$id} // %Projection{cleanup-projection-name $id};
}

my $lastellipse = '';
my $name;
my $eccentricity;
my $radius;
my ($k1, $k2, $k3, $k4);

sub set-ellipsoid (Str $ellipsoid) is export {
    my $ell = %Geo::Ellipsoids::Ellipsoid{$ellipsoid}
           // %Geo::Ellipsoids::Ellipsoid{Geo::Ellipsoids::cleanup-ellipsoid-name $ellipsoid};
    fail("Unknown ellipsoid $ellipsoid") unless $ell.defined;
    $eccentricity = sqrt $ell.eccentricity-squared;
    $radius       = $ell.semi-major-axis;
}
  
set-ellipsoid 'WGS-84'; # As good a default as any

# These are globals. This might create problems if you try to
# use this module in a threaded environment. It should not be
# a problem if all threads are using the same projection.

my $φ1;
my $φ2;
my $φ0;
my $λ0;
my $false-easting;
my $false-northing;

# projection invariants for latlon-to-lcc and lcc-to-latlon

my $m1;
my $m2;
my $t0;
my $t1;
my $t2;
my $n;
my $F;
my $ρ0;

sub make-projection-constants($lat0, $lat1, $lat2, $long0, $fe, $fn, $ell?) {
  $φ0             = $lat0;
  $φ1             = $lat1;
  $φ2             = $lat2;
  $λ0             = $long0;
  $false-easting  = $fe;
  $false-northing = $fn;
  set-ellipsoid($ell) if $ell.defined && $ell;
  my \e := $eccentricity;
  $m1 = cos($φ1)/sqrt(1 - e² × (sin $φ1)²);
  $m2 = cos($φ2)/sqrt(1 - e² × (sin $φ2)²);
  $t0 = tan(π/4 - $φ0/2) ÷ ((1 - e × sin $φ0) ÷ (1 + e × sin $φ0)) ** (e/2);
  $t1 = tan(π/4 - $φ1/2) ÷ ((1 - e × sin $φ1) ÷ (1 + e × sin $φ1)) ** (e/2);
  $t2 = tan(π/4 - $φ2/2) ÷ ((1 - e × sin $φ2) ÷ (1 + e × sin $φ2)) ** (e/2);
  $n  = (ln $m1 - ln $m2) ÷ (ln $t1 - ln $t2);
  $F  = $m1 ÷ ($n × $t1 ** $n);
  $ρ0 = $radius × $F × $t0 ** $n;
}

proto sub set-projection(|) is export { * }

multi sub set-projection(Str $name) {
  my $pr = projection-info($name);
  fail "Unknown projection $name" unless $pr.defined;
  make-projection-constants(
      $pr.lat0,
      $pr.lat1,
      $pr.lat2,
      $pr.long0,
      $pr.false-easting,
      $pr.false-northing,
      $pr.ellipsoid,
  );
}

multi sub set-projection($new-φ1, $new-φ2, $new-φ0, $new-λ0, $new-false-easting, $new-false-northing, $ellipsoid?) {
  make-projection-constants(
    $new-φ0,
    $new-φ1,
    $new-φ2,
    $new-λ0,
    $new-false-easting,
    $new-false-northing,
    $ellipsoid // '',
  );
}

# Expects Latitude, Longitude in degrees
# Returns LCC Easting, LCC Northing

proto latlon-to-lcc(|) is export { * }

multi sub latlon-to-lcc($point where Point|PointZ|PointM|PointZM) {
    my ($x, $y) = samewith($point.x, $point.y);
    Point.new(:$x, :$y);
}
  
multi sub latlon-to-lcc($line where LineString|LineStringZ|LineStringM|LineStringZM) {
    LineString.new(points => $line.points.map({.samewith}));
}

multi sub latlon-to-lcc($line where LinearRing|LinearRingZ|LinearRingM|LinearRingZM) {
    LinearRing.new(points => $line.points.map({.samewith}));
}

multi sub latlon-to-lcc($polygon where Polygon|PolygonZ|PolygonM|PolygonZM) {
    Polygon.new(rings => $polygon.rings.map({.samewith}));
}

multi sub latlon-to-lcc($line where MultiPoint|MultiPointZ|MultiPointM|MultiPointZM) {
    MultiPoint.new(points => $line.points.map({.samewith}));
}

multi sub latlon-to-lcc($lines where MultiLineString|MultiLineStringZ|MultiLineStringM|MultiLineStringZM) {
    MultiLineString.new(linestrings => $lines.lines.map({.samewith}));
}

multi sub latlon-to-lcc($multipolygon where MultiPolygon|MultiPolygonZ|MultiPolygonM|MultiPolygonZM) {
    MultiPolygon.new(polygons => $multipolygon.polygons.map({.samewith}));
}

multi sub latlon-to-lcc($phs where PolyhedralSurface|PolyhedralSurfaceZ|PolyhedralSurfaceM|PolyhedralSurfaceZM) {
    PolyhedralSurface.new(polygons => $phs.polygons.map({.samewith}));
}

multi sub latlon-to-lcc($tin where TIN|TINZ|TINM|TINZM) {
    TIN.new(points => $tin.points.map({.samewith}));
}

multi sub latlon-to-lcc($triangle where Triangle|TriangleZ|TriangleM|TINZM) {
    Triangle.new(points => $triangle.points.map({.samewith}));
}

multi sub latlon-to-lcc($gc where GeometryCollection|GeometryCollectionZ|GeometryCollectionM|GeometryCollectionZM) {
    GeometryCollection.new(geometries => $gc.geometries.map({.samewith}));
}
  
multi sub latlon-to-lcc(Real $φ, Real $λ) {
  fail "Longitude value ($λ) invalid." unless -180 ≤ $λ ≤ 180;
  fail "Latitude value ($φ) invalid."  unless  -90 ≤ $φ ≤  90;
  my \a  := $radius;
  my \e  := $eccentricity;
  my \λ   = $λ°;
  my \λ0 := $λ0;
  my \φ   = $φ°;
  my \φ0 := $φ0;
  my \φ1 := $φ1;
  my \φ2 := $φ2;
  my \t0 := $t0;
  my \t1 := $t1;
  my \t2 := $t2;
  my \m1 := $m1;
  my \m2 := $m2;
  my \n  := $n;
  my \F  := $F;
  my \ρ0 := $ρ0;

  my \t  = tan(π/4 - φ /2) ÷ ((1 - e × sin φ ) ÷ (1 + e × sin φ )) ** (e/2);

  my \m  = cos(φ)/sqrt( 1 - e² × (sin φ )²);

  my \ρ  = a × F × t ** n;
  my \k  = m1 × t ** n ÷ (m × t1 ** n);
  my \θ  = n × (λ - λ0);
  my \x  = ρ × sin θ;
  my \y  = ρ0 - ρ × cos θ;
  (x + $false-easting, y + $false-northing);
}

# Expects LCC Easting, LCC Northing (uses previously set projection)
# Returns Latitude, Longitude in degrees

proto lcc-to-latlon(|) is export { * }

multi sub lcc-to-latlon($point where Point|PointZ|PointM|PointZM) {
    my ($lat, $lon) = samewith($point.x, $point.y);
    Point.new(x => $lon, y => $lat);
}

multi sub lcc-to-latlon($line where LineString|LineStringZ|LineStringM|LineStringZM) {
    LineString.new(points => $line.points.map({.samewith}));
}

multi sub lcc-to-latlon($line where LinearRing|LinearRingZ|LinearRingM|LinearRingZM) {
    LinearRing.new(points => $line.points.map({.samewith}));
}

multi sub lcc-to-latlon($polygon where Polygon|PolygonZ|PolygonM|PolygonZM) {
    Polygon.new(rings => $polygon.rings.map({.samewith}));
}

multi sub lcc-to-latlon($line where MultiPoint|MultiPointZ|MultiPointM|MultiPointZM) {
    MultiPoint.new(points => $line.points.map({.samewith}));
}

multi sub lcc-to-latlon($lines where MultiLineString|MultiLineStringZ|MultiLineStringM|MultiLineStringZM) {
    MultiLineString.new(linestrings => $lines.lines.map({.samewith}));
}

multi sub lcc-to-latlon($multipolygon where MultiPolygon|MultiPolygonZ|MultiPolygonM|MultiPolygonZM) {
    MultiPolygon.new(polygons => $multipolygon.polygons.map({.samewith}));
}

multi sub lcc-to-latlon($phs where PolyhedralSurface|PolyhedralSurfaceZ|PolyhedralSurfaceM|PolyhedralSurfaceZM) {
    PolyhedralSurface.new(polygons => $phs.polygons.map({.samewith}));
}

multi sub lcc-to-latlon($tin where TIN|TINZ|TINM|TINZM) {
    TIN.new(points => $tin.points.map({.samewith}));
}

multi sub lcc-to-latlon($triangle where Triangle|TriangleZ|TriangleM|TINZM) {
    Triangle.new(points => $triangle.points.map({.samewith}));
}

multi sub lcc-to-latlon($gc where GeometryCollection|GeometryCollectionZ|GeometryCollectionM|GeometryCollectionZM) {
    GeometryCollection.new(geometries => $gc.geometries.map({.samewith}));
}
  
multi sub lcc-to-latlon(Real $x, Real $y) {
  my \e  := $eccentricity;
  my \a  := $radius;
  my \λ0 := $λ0;
  my \φ0 := $φ0;
  my \φ1 := $φ1;
  my \φ2 := $φ2;
  my \m1 := $m1;
  my \m2 := $m2;
  my \t0 := $t0;
  my \t1 := $t1;
  my \t2 := $t2;
  my \n  := $n;
  my \F  := $F;
# everything above here depends only on the projection
# and so is calculated when the projection is set
  my \ρ0 = sign(n) × a × F × t0 ** n;
  my \x  = sign(n) × ($x - $false-easting);
  my \y  = sign(n) × ($y - $false-northing);
  my \ρ  = sign(n) × sqrt(x² + (ρ0 - y)²);
  my \t  = (ρ / (a * F)) ** (1/n);
  my \χ  = π/2 - 2 × atan t;
  my \φ  = χ + (e²/2 + 5 × e⁴ /  24 +      e⁶ /  12 +  13 × e⁸ /   360) × sin(2 × χ)
             + (       7 × e⁴ /  48 + 29 × e⁶ / 240 + 811 × e⁸ / 11520) × sin(4 × χ)
             + (                       7 × e⁶ / 120 +  81 × e⁸ /  1120) × sin(6 × χ)
             + (                                     4279 × e⁸ /161280) × sin(8 × χ);

  my \θ  = atan(x ÷ (ρ0 - y));
  my \λ  = θ ÷ n + λ0;
  (φ × rad2deg, λ × rad2deg);
}
