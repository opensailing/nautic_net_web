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

export function interactiveMap(hook) {
  let divElement = hook.el;
  hook.previousLayer = undefined;

  var map = Leaflet.map(divElement, { preferCanvas: true }).setView(
    [42.27, -70.997],
    14
  );

  var polyline = Leaflet.polyline([], { color: "red" }).addTo(map);
  let trackCoordinates = [];

  Leaflet.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
    maxZoom: 19,
    attribution: "© OpenStreetMap",
  }).addTo(map);

  var marker = L.marker([42.27, -70.997]).addTo(map);
  marker.bindPopup("Boat Node");

  map.on("zoomlevelschange resize load moveend viewreset", (e) => {
    const {
      _southWest: { lat: min_lat, lng: min_lon },
      _northEast: { lat: max_lat, lng: max_lon },
    } = map.getBounds();

    const bounds = { min_lat, max_lat, min_lon, max_lon };

    const position = document.getElementById("position").value;
    const zoom_level = map.getZoom();
    hook.pushEvent("change_bounds", {
      bounds,
      position,
      zoom_level,
    });
  });

  window.addEventListener("handleSetPosition", (e) => {
    // "set_position";
    const position = document.getElementById("position").value;
    hook.pushEvent("set_position", { position, zoom_level: map.getZoom() });
  });

  window.addEventListener(`phx:track_coordinates`, (e) => {
    const {
      detail: { coordinates },
    } = e;

    trackCoordinates = coordinates;
  });

  window.addEventListener(`phx:marker_coordinates`, (e) => {
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
    hook.timeoutHandler && clearInterval(hook.timeoutHandler);

    if (play) {
      const fps = 30;

      const timeoutHandler = setInterval(() => {
        const posElement = window.document.getElementById("position");
        const inc = 30;

        if (!posElement) {
          clearInterval(timeoutHandler);
          return;
        }

        if (
          parseInt(posElement.value) >=
          parseInt(posElement.max) - (inc + 1)
        ) {
          clearInterval(timeoutHandler);
        } else {
          posElement.stepUp(inc);
          const position = posElement.value;
          hook.pushEvent("set_position", {
            position,
            zoom_level: map.getZoom(),
          });
        }
      }, 1000 / fps);

      hook.timeoutHandler = timeoutHandler;
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

  window.addEventListener(`phx:add_current_markers`, (e) => {
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

    const binData = e.detail.current_data;
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
    hook.previousLayer && map.removeLayer(hook.previousLayer);
    hook.previousLayer = layer;
  });
}
