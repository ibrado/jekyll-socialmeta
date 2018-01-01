"use strict";
var system = require('system'),
    fs = require('fs'),
    page = require('webpage').create(),
    address, output_dir, origin, imgTop, imgLeft, dimensions, imgWidth, imgHeight,
    viewDimensions, viewWidth, viewHeight, scroll, scrollTop, scrollLeft,
    zoom, bgStyle, imgStyle;

page.onResourceError = function(resourceError) {
  system.stdout.writeLine('debug '+resourceError.errorString+': '+resourceError.url);
  page.reason_url = resourceError.url;
  page.reason = resourceError.errorString;
};

var myBase = system.env['site_base'];

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

page.open(address, function(status) {
  if(status !== 'success') {
    system.stdout.writeLine('error Unable to render '+address)
    system.stdout.writeLine('error '+page.reason+' at '+page.reason_url)
    phantom.exit(1);

  } else {

    // Twitter Card, 1260x630 default
    var ts, crop;
    
    render(output_dir  + 'tcl-ts.jpg', function() {
      var mtime  = fs.lastModified(output_dir  + 'tcl-ts.jpg')
      ts = Math.floor(mtime.valueOf() / 1000);

      // Open Graph 1200x630
      crop = (imgWidth - (imgWidth / 1.05)) / 2;
      
      page.clipRect = { top: imgTop, left: imgLeft + crop, width: imgWidth - 2*crop, height: imgHeight };

      render(output_dir + 'og-ts.jpg', function() {
        // Twitter Card, Small 630x630
        crop = (imgWidth - imgHeight) / 2;
        page.clipRect = { top: imgTop, left: imgLeft + crop, width: imgWidth - 2*crop, height: imgHeight };

        render(output_dir + 'tcs-ts.jpg', function() {
          system.stdout.writeLine('success ' + ts);
          phantom.exit();
        })
      }) 
    })
  }
});
