import Leaflet from "leaflet";
import "leaflet-canvas-markers";
import { GeoData } from "./geodata_pb.js";

const colorArrayToRgb = ([r, g, b]) => `rgb(${r}, ${g}, ${b})`;

const colorLerp = ([s_r, s_g, s_b], [e_r, e_g, e_b], t) => {
  const lerp = (x, y, t) => Math.round(x + (y - x) * t);
  return colorArrayToRgb([
    lerp(s_r, e_r, t),
    lerp(s_g, e_g, t),
    lerp(s_b, e_b, t),
  ]);
};

const interpolateColors = (value) => {
  const config = [
    [0, [0, 0, 255]],
    [0.56, [0, 255, 255]],
    [1.13, [0, 127, 0]],
    [1.69, [255, 255, 0]],
    [2.25, [255, 0, 0]],
  ];

  for (let i = 0; i < config.length - 1; i++) {
    const [lowerBound, startColor] = config[i];
    const [upperBound, endColor] = config[i + 1];
    if (value >= lowerBound && value < upperBound) {
      const t = (value - lowerBound) / (upperBound - lowerBound);
      return colorLerp(startColor, endColor, t);
    }
  }

  return colorArrayToRgb(config[config.length - 1][1]);
};

const drawArrowIcon = (ctx, speed, width, height) => {
  const color = interpolateColors(speed);
  // 14 is the original viewport width and height for the SVG
  const xScale = width / 14;
  const yScale = height / 14;
  const path = new Path2D(
    "M 12.765625 7 L 8.375 10.636719 L 8.75 11.082031 L 14 6.695312 L 8.75 2.332031 L 8.375 2.777344 L 12.765625 6.417969 L 0 6.417969 L 0 7 Z M 12.765625 7"
  );
  ctx.strokeStyle = color;
  ctx.scale(xScale, yScale);
  ctx.stroke(path);
  return ctx;
};

L.Canvas.include({
  _updateCustomIconMarker: function (layer) {
    if (!this._drawing || layer._empty()) {
      return;
    }

    const p = layer._point;
    let ctx = this._ctx;
    const {
      options: { speed, rotationAngle, width, height },
    } = layer;
    const h = Math.max(Math.round(height), 1);
    const w = Math.max(Math.round(width), 1);
    this._layers[layer._leaflet_id] = layer;

    const theta = ((rotationAngle - 90) * Math.PI) / 180;

    ctx.save();
    ctx.translate(p.x, p.y);
    ctx.rotate(theta);
    ctx = drawArrowIcon(ctx, speed, w, h);
    ctx.restore();
  },
});

const CustomIconMarker = L.CircleMarker.extend({
  _updatePath: function () {
    this._renderer._updateCustomIconMarker(this);
  },
});

class BoatView {
  boatId = null;
  map = null;
  marker = null;
  polyline = null;
  trackCoordinates = [];

  constructor(map, boatId, trackCoordinates, trackColor) {
    this.boatId = boatId;
    this.map = map;
    this.trackCoordinates = trackCoordinates;
    this.marker = Leaflet.marker([0, 0]).addTo(map);
    this.polyline = Leaflet.polyline([], { color: trackColor }).addTo(map);
  }

  setVisible(visible) {
    if (visible) {
      this.marker.addTo(this.map);
      this.polyline.addTo(this.map);
    } else {
      this.marker.removeFrom(this.map);
      this.polyline.removeFrom(this.map);
    }
  }

  setTime(startTime, endTime, inspectTime) {
    const newCoords = this.trackCoordinates.filter(
      (c) => c.time >= startTime && c.time <= inspectTime
    );
    const lastCoord = newCoords[newCoords.length - 1];

    this.polyline.setLatLngs(newCoords.map((c) => [c.lat, c.lng]));

    if (lastCoord) {
      this.marker.setLatLng([lastCoord.lat, lastCoord.lng]);

      // TODO: Rotate marker based on lastCoord.heading_rad (CustomIconMarker)
    }
  }

  destroy() {
    this.setVisible(false);
  }
}

const LeafletHook = {
  mounted() {
    let divElement = this.el;
    this.previousLayer = undefined;

    var map = Leaflet.map(divElement, { preferCanvas: true }).setView(
      [42.27, -70.997],
      14
    );

    // var polyline = Leaflet.polyline([], { color: "red" }).addTo(map);
    // let trackCoordinates = [];

    Leaflet.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
      maxZoom: 19,
      attribution: "© OpenStreetMap",
    }).addTo(map);

    // var marker = L.marker([42.27, -70.997]).addTo(map);
    // marker.bindPopup("Boat Node");

    map.on("zoomlevelschange resize load moveend viewreset", (e) => {
      const {
        _southWest: { lat: min_lat, lng: min_lon },
        _northEast: { lat: max_lat, lng: max_lon },
      } = map.getBounds();

      const bounds = { min_lat, max_lat, min_lon, max_lon };

      const position = document.getElementById("position").value;
      const zoom_level = map.getZoom();
      this.pushEvent("change_bounds", {
        bounds,
        position,
        zoom_level,
      });
    });

    this.boatViews = [];

    window.addEventListener("phx:boat_views", (e) => {
      const params = e.detail;

      this.boatViews.forEach((bv) => bv.destroy());

      this.boatViews = params.boat_views.map((newBv) => {
        return new BoatView(
          map,
          newBv.boat_id,
          newBv.coordinates,
          newBv.track_color
        );
      });
    });

    window.addEventListener("phx:clear_boat_views", () => {
      this.boatViews.forEach((bv) => bv.destroy());
    });

    window.addEventListener("phx:add_boat_view", (e) => {
      const params = e.detail;

      this.boatViews.push(
        new BoatView(
          map,
          params.boat_view.boat_id,
          params.boat_view.coordinates,
          params.boat_view.track_color
        )
      );
    });

    window.addEventListener(
      "phx:set_boat_visible",
      ({ detail: { boat_id, visible } }) => {
        const boatView = this.boatViews.find((bv) => bv.boatId == boat_id);

        if (boatView) {
          boatView.setVisible(visible);
        }
      }
    );

    window.addEventListener("phx:map_state", (e) => {
      const params = e.detail;

      // Update BoatView markers and tracks
      if (params.range_start_at && params.range_end_at && params.inspect_at) {
        this.boatViews.forEach((bv) => {
          bv.setTime(
            params.range_start_at,
            params.range_end_at,
            params.inspect_at
          );
        });
      }
    });

    window.addEventListener("handleSetPosition", (e) => {
      // "set_position";
      const position = document.getElementById("position").value;
      this.pushEvent("set_position", { position, zoom_level: map.getZoom() });
    });

    window.addEventListener(`phx:track_coordinates`, (e) => {
      const {
        detail: { coordinates },
      } = e;

      trackCoordinates = coordinates;
    });

    window.addEventListener(`phx:marker_coordinate`, (e) => {
      const {
        detail: { latitude, longitude },
      } = e;

      marker.setLatLng({ lat: latitude, lng: longitude });
    });

    window.addEventListener(`phx:marker_position`, (e) => {
      const {
        detail: { position },
      } = e;

      const [latitude, longitude] = trackCoordinates[position];
      marker.setLatLng({ lat: latitude, lng: longitude });
      polyline.setLatLngs(trackCoordinates.slice(0, position));
    });

    window.addEventListener("animateTime", ({ detail: { play } }) => {
      this.timeoutHandler && clearInterval(this.timeoutHandler);

      if (play) {
        const playback_speed = window.document.getElementById("playback_speed");
        const speed = parseInt(playback_speed.value)

        const timeoutHandler = setInterval(() => {
          

          const posElement = window.document.getElementById("position");
          
          if (!posElement) {
            clearInterval(timeoutHandler);
            return;
          }

          if (
            parseInt(posElement.value) >=
            parseInt(posElement.max) - (speed + 1)
          ) {
            clearInterval(timeoutHandler);
          } else {
            posElement.stepUp(speed);
            const position = posElement.value;
            this.pushEvent("set_position", {
              position,
              zoom_level: map.getZoom(),
              play: play
            });
          }
        }, 1000 / speed);

        this.timeoutHandler = timeoutHandler;
      }else{
        this.pushEvent("set_position", {
          play: play
        });
      }
    });

    window.addEventListener(`phx:map_view`, (e) => {
      map.setView([e.detail.latitude, e.detail.longitude], 14);
    });

    window.addEventListener(`phx:clear_polyline`, (_e) => {
      polyline.setLatLngs([]);
    });

    window.addEventListener(`phx:toggle_track`, (e) => {
      if (e.detail.value) {
        polyline.addTo(map);
      } else {
        polyline.remove();
      }
    });

    window.addEventListener(`phx:add_water_markers`, (e) => {
      const markerBaseColor = interpolateColors(0);

      const canvasRenderer = L.canvas({ padding: 0 });

      const geojsonMarkerOptions = {
        radius: 0.5,
        fillColor: markerBaseColor,
        color: markerBaseColor,
        weight: 1,
        opacity: 1,
        fillOpacity: 1,
        keyboard: false,
        renderer: canvasRenderer,
      };

      const binData = e.detail.water_data;
      const deserialized = GeoData.deserializeBinary(binData);
      const data = deserialized.array[0];

      const geojsonData = data.map(([lat, lon, speed, direction]) => {
        return {
          type: "Feature",
          geometry: {
            type: "Point",
            coordinates: [lon, lat],
          },
          properties: { speed, direction },
        };
      });

      const layer = L.geoJSON(geojsonData, {
        pointToLayer: function (feature, latlng) {
          const { direction, speed } = feature.properties;

          if (speed == 0) {
            return undefined;
          }

          const farZoom = map.getZoom() < 12;
          // Remove "zero" currents for farther zoom levels
          if (!farZoom && speed > 0 && speed < 0.05) {
            return L.circleMarker(latlng, geojsonMarkerOptions);
          }

          // Remove "slow" currents for farther zooms
          if (farZoom && speed < 0.2) {
            return undefined;
          }

          const color = interpolateColors(speed);

          let scale = 1;
          if (speed > 0 && speed <= 0.56) {
            const minSize = 0.4;
            scale = minSize + (speed / 0.56) * (1 - minSize);
          }

          return new CustomIconMarker(latlng, {
            ...geojsonMarkerOptions,
            rotationAngle: direction,
            speed,
            width: 12 * scale,
            height: 6 * scale,
            fillColor: color,
            color: color,
          });
        },
      });

      map.addLayer(layer);
      this.previousLayer && map.removeLayer(this.previousLayer);
      this.previousLayer = layer;
    });

    window.addEventListener(`phx:clear_water_markers`, (e) => {
      this.previousLayer && map.removeLayer(this.previousLayer);
      this.previousLayer = undefined;
    });
  },
};

export default LeafletHook;
