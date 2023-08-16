import noUiSlider from "nouislider";

export default {
  mounted() {
    let { min, max, from, to } = this.el.dataset;
    min = parseInt(min);
    from = parseInt(from);
    max = parseInt(max);
    to = parseInt(to);

    noUiSlider.create(this.el, {
      start: [from, to],
      connect: true,
      behaviour: "tap-drag",
      range: { min, max },
    });

    this.el.noUiSlider.on("update", ([min, max], _handle) => {
      this.pushEvent("update_range", { min, max });
    });

    this.handleEvent("set_enabled", ({ enabled }) => {
      if (enabled) {
        this.el.removeAttribute("disabled");
      } else {
        this.el.setAttribute("disabled", true);
      }
    });

    this.handleEvent("configure", ({ min, max }) => {
      this.el.noUiSlider.updateOptions({ range: { min, max } });
      this.el.noUiSlider.set([min, max]);
      this.el.noUiSlider.reset();
    });
  },
};
