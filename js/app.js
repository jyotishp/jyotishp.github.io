var myElement = document.querySelector("nav");
// construct an instance of Headroom, passing the element
var headroom  = new Headroom(myElement, {
  "offset": 250,
  "tolerance": 3,
});
// initialise
headroom.init(); 

// var sidebar = new stickySidebar('.comments-box', {topSpacing: 20});