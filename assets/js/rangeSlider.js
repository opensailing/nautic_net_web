import noUiSlider from 'nouislider';


export function rangeSlider(hook) {
  let divElement = hook.el;
  const { max } = divElement.dataset;

  noUiSlider.create(divElement, {
    start: [0, parseFloat(max)],
    connect: true,
    behaviour: "tap-drag",
    range: {
      'min': 0,
      'max': parseFloat(max)
    }
  });

  divElement.noUiSlider.on('update', function ([min, max], _handle) {
    hook.pushEvent('update_range', { min: min, max: max });
  });
}
