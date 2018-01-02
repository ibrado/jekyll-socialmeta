"use strict";
var system = require('system'),
    fs = require('fs'),
    page = require('webpage').create(),
    address, output_dir, origin, imgTop, imgLeft, dimensions, imgWidth, imgHeight,
    viewDimensions, viewWidth, viewHeight, scroll, scrollTop, scrollLeft,
    zoom, bgStyle, imgStyle;

var formats = system.env['image_formats'];
var page_snap = parseInt(system.env['page_snap']);

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

  system.stderr.writeLine('Main render ==========================='); 
  system.stderr.writeLine('clipRect: '+imgTop+','+imgLeft+' '+imgWidth+'x'+imgHeight); 
  system.stderr.writeLine('viewPort: '+viewWidth+'x'+viewHeight); 
  system.stderr.writeLine('    zoom: '+zoom); 
  system.stderr.writeLine(''); 

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
    if(page_snap) {
      page.clipRect = { top: imgTop, left: imgLeft, width: imgWidth - 2*crop, height: imgHeight };
      page.viewportSize = { width: imgWidth - 2*crop, height: imgHeight};
    } else {
      page.clipRect = { top: imgTop, left: imgLeft + crop, width: imgWidth - 2*crop, height: imgHeight };
      page.viewportSize = { width: viewWidth, height: viewHeight };
    }

    system.stderr.writeLine('Rendering OG'); 
    render(output_dir + 'og-ts.jpg', next);

  } else {
    next();
  }
}

function render_tcl(next) {
  if(has_format('tcl')) {
    // Twitter Card, 1260x630 default
    if(page_snap) {
      page.viewportSize = { width: imgWidth, height: imgHeight};
    } else {
      page.viewportSize = { width: viewWidth, height: viewHeight };
    }

    // No cropping needed as requested screen is TCL's aspect ratio
    page.clipRect = { top: imgTop, left: imgLeft, width: imgWidth, height: imgHeight };

    system.stderr.writeLine('Rendering TCL');
    render(output_dir  + 'tcl-ts.jpg', next);

  } else {
    next();
  }
}

function render_tcs(next) {
  if(has_format('tcs')) {
    // Twitter Card Summary, 630x630 default
    if(page_snap) {
      page.clipRect = { top: imgTop, left: imgLeft, width: imgHeight, height: imgHeight };
      page.viewportSize = { width: imgHeight, height: imgHeight};
    } else {
      var crop = (imgWidth - imgHeight) / 2;
      page.clipRect = { top: imgTop, left: imgLeft + crop, width: imgWidth - 2*crop, height: imgHeight };
      page.viewportSize = { width: viewHeight, height: viewHeight};
    }

    system.stderr.writeLine('Rendering TCS'); 
    render(output_dir + 'tcs-ts.jpg', next);

  } else {
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

  if(ts_base == null) {
    // Nothing rendered
    system.stdout.writeLine('error Nothing rendered.')
    phantom.exit(1);

  } else {
    system.stderr.writeLine('Getting timestamp of '+output_dir+ts_base+'-ts.jpg');
    var mtime = fs.lastModified(output_dir  + ts_base + '-ts.jpg')
    var ts = Math.floor(mtime.valueOf() / 1000);

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
