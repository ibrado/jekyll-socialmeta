"use strict";
var system = require('system'),
    fs = require('fs'),
    page = require('webpage').create(),
    address, output_dir, origin, imgTop, imgLeft, dimensions, imgWidth, imgHeight,
    viewDimensions, viewWidth, viewHeight, scroll, scrollTop, scrollLeft,
    zoom, bgStyle, imgStyle;

var formats = system.env['image_formats'];

system.stderr.writeLine('screenshot.js FORMATS: '+formats);

page.onResourceError = function(resourceError) {
  system.stdout.writeLine('debug '+resourceError.errorString+': '+resourceError.url);
  page.reason_url = resourceError.url;
  page.reason = resourceError.errorString;
};

address = system.args[1];
output_dir = system.args[2];
origin = system.args[3];
dimensions  = system.args[4];
viewDimensions = system.args[5];
scroll = system.args[6];
zoom = parseFloat(system.args[7]);
bgStyle = system.args[8];
imgStyle = system.args[9];

var tmp = origin.split(',');
imgTop = parseInt(tmp[0]);
imgLeft = parseInt(tmp[1]);

tmp = dimensions.split('x');
imgWidth = parseInt(tmp[0]);
imgHeight = parseInt(tmp[1]);

tmp = viewDimensions.split('x');
viewWidth = parseInt(tmp[0]);
viewHeight = parseInt(tmp[1]);

tmp = scroll.split(',');
scrollTop = parseInt(tmp[0]);
scrollLeft = parseInt(tmp[1]);

page.viewportSize = { width: viewWidth, height: viewHeight};
page.clipRect = { top: imgTop, left: imgLeft, width: imgWidth, height: imgHeight };
page.zoomFactor = zoom;

function has_format(fmt) {
  return formats.indexOf(fmt) >= 0
}

function render(output, next) {
  window.setTimeout(function () {
    if(address.match(/\.(gif|jpe?g|png|tiff|bmp|ico|cur|psd|svg|webp)$/i)) {
      page.evaluate ( function(bgStyle, imgStyle) {
        document.body.style.cssText += bgStyle;
        var imgs = document.body.getElementsByTagName("img");
        imgs[0].style.cssText += imgStyle;
      }, bgStyle, imgStyle);

    } else {
      page.scrollPosition = { top: scrollTop, left: scrollLeft };
    }

    page.render(output, {format: 'jpg', quality: '100'});
    next();

  });
}

function render_og(next) {
  if(has_format('og')) {
    // Open Graph 1200x630
    var crop = (imgWidth - (imgWidth / 1.05)) / 2;
    page.clipRect = { top: imgTop, left: imgLeft + crop, width: imgWidth - 2*crop, height: imgHeight };

    system.stderr.writeLine('screenshot.js Rendering OG');
    render(output_dir + 'og-ts.jpg', next);
  } else {
    system.stderr.writeLine('screenshot.js Not endering OG');
    next();
  }
}

function render_tcl(next) {
  // Twitter Card, 1260x630 default
  if(has_format('tcl')) {
    // No cropping needed
    page.clipRect = { top: imgTop, left: imgLeft, width: imgWidth, height: imgHeight };
    system.stderr.writeLine('screenshot.js Rendering TCL');
    render(output_dir  + 'tcl-ts.jpg', next);
  } else {
    system.stderr.writeLine('screenshot.js Not rendering TCL');
    next();
  }
}

function render_tcs(next) {
  if(has_format('tcs')) {
    var crop = (imgWidth - imgHeight) / 2;
    page.clipRect = { top: imgTop, left: imgLeft + crop, width: imgWidth - 2*crop, height: imgHeight };

    system.stderr.writeLine('screenshot.js Rendering TCS');
    render(output_dir + 'tcs-ts.jpg', next);
  } else {
    system.stderr.writeLine('screenshot.js NOT rendering TCS');
    next();
  }
}

function render_done() {
  var ts_base = null;

  if(has_format('og')) {
    ts_base = 'og';
  } else if(has_format('tcl')) {
    ts_base = 'tcl';
  } else if(has_format('tcs')) {
    ts_base = 'tcs';
  }

  system.stderr.writeLine('screenshot.js TS_BASE IS '+ts_base);
  if(ts_base == null) {
    // Nothing rendered
    system.stderr.writeLine('screenshot.js NOTHING rendered');
    system.stdout.writeLine('error Nothing rendered.')
    phantom.exit(1);

  } else {
    var mtime = fs.lastModified(output_dir  + ts_base + '-ts.jpg')
    var ts = Math.floor(mtime.valueOf() / 1000);

    system.stderr.writeLine('screenshot.js SUCCESS! ts='+ts);
    system.stdout.writeLine('success ' + ts);
    phantom.exit();
  }
}

page.open(address, function(status) {
  if(status !== 'success') {
    system.stdout.writeLine('error Unable to render '+address)
    system.stdout.writeLine('error '+page.reason+' at '+page.reason_url)
    phantom.exit(1);

  } else {

    render_og( function() {
      render_tcl( function() {
        render_tcs( function() {
          render_done()
        })
      })
    });
  }
});
