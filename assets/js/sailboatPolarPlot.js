import embed from "vega-embed";

const SailboatPolarPlotHook = {
  mounted() {
    let divElement = this.el;
    window.addEventListener("phx:update_polar_plot", (e) => {
      const params = e.detail;
      console.log(params);
      const spec = JSON.parse(params.json_spec);
      console.log(spec);
      embed(`#${divElement.id}`, spec, {
        renderer: "svg",
        actions: {
          export: { svg: true, png: true },
          source: false,
          compiled: false,
          editor: false,
        },
        downloadFileName: "polar_plot",
      });
    });

    this.pushEvent("mounted", {});
  },
};

export default SailboatPolarPlotHook;
