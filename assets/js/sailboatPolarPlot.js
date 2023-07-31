import embed from "vega-embed";

const SailboatPolarPlotHook = {
  mounted() {
    let divElement = this.el;
    window.addEventListener("phx:update_polar_plot", (e) => {
      const params = e.detail;
      console.log(params);
      const spec = JSON.parse(params.json_spec);
      console.log(spec);
      embed(`#${divElement.id}`, spec, { width: 1000, height: 1000 });
    });
  },
};

export default SailboatPolarPlotHook;
