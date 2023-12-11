
//This code is meant to be run on Google Earth Engine
//code link: https://code.earthengine.google.com/0279a285caa496ae638011c358c75f08


/////////////// MANAGE RASTER DATA ///////////////

var lcms = ee.ImageCollection("USFS/GTAC/LCMS/v2022-8"),
    nfpors = ee.FeatureCollection("users/tymc5571/West_NFPORS_2010_2021"),
    frg = ee.ImageCollection("LANDFIRE/Fire/FRG/v1_2_0");

print("NFPORS", nfpors.limit(50));

// Filter the LCMS by image name containing "LCMS_CONUS",
// to only include the Land Cover band, and to include the dates of interest
var lcmsInterest = lcms.filter(ee.Filter.stringContains('system:index', 'LCMS_CONUS')).select("Land_Cover").filterDate('2010-01-01', '2021-12-31');

print(lcmsInterest);

//Filter the FRG data
// Reclass FRC data to low/mixed (1) vs. replacement (2) vs. masked (3)
// (Same classification as used by Rud Platt: https://code.earthengine.google.com/219f9f57df135f2fbfd69e2506ea5f9c)
var frcCONUS = frg.filterMetadata('system:index','contains','CONUS').first();
var frcRcl = frcCONUS.remap([1,2,3,4,5,111,112,131,132,133],[1,2,1,2,2,3,3,3,3,3],0,'FRG').rename('frcRcls');
var frcLowMix = frcRcl.eq(1).rename('frcLowMix');
var frcReplace = frcRcl.eq(2).rename('frcReplace');

//Map.addLayer(frcRcl);



///////////////////// EXTRACTION FUNCTIONS /////////////////

// A function to extract the values from an imageCollection with each image as a year.
// To the input feature collection by MEAN
// And include the date of the image extracted
// (Should be used by mapping over the collection)
// PARAMETERS
// collection: the featurecollection
// nm: the name of the output property, as a string (e.g. "LandCover")
var extractMeanImageValuesPlusYear = function(collection, nm) {
  var wrap = function(image) {
    var imageDate = image.date().format('YYYY'); // Get the image year
    var properties = image.reduceRegions({
      collection: collection,
      reducer: ee.Reducer.mean().setOutputs([nm]), //reduce and set output name
      scale: 30, 
      crs: image.projection() // Match the projection of the image
    });
    
    // Construct year string
    var yrNm = ee.String(nm).cat("_Year");
    
    // Rename the properties to include the image date as a property
    var renamedProperties = properties.map(function(feature) {
      return feature.set(yrNm, ee.String(imageDate));
    });
    return renamedProperties;
  };
  return(wrap);
};

// Function to pull the values from a single image, reduced by mean to a featurecollection
// PARAMETERS
// image: the image to reduce
// collection: the featurecollection to use
// nm: the name of the output property, as a string (e.g. "FRG")

var addMeanImageValues = function(image, collection, nm) {
  var properties = image.reduceRegions({
    collection: collection,
    reducer: ee.Reducer.mean().setOutputs([nm]),
    scale: 30,
    crs:image.projection()
  });
  return(properties);
};



///////////////// APPLY THE FUNCTIONS & CHECK OUTPUTS ////////////////

// Apply the addLCMSImageValues function to each image in the ImageCollection
var imageValueCollection = lcmsInterest.map(extractMeanImageValuesPlusYear(nfpors,"LandCover")).flatten();
print(imageValueCollection.limit(50));

// Use the addMeanImageValues function
var imageValueCollection = addMeanImageValues(frcRcl, imageValueCollection, "FRG");
print(imageValueCollection.limit(50));



///////////////////// Export /////////////////////

Export.table.toDrive({
  collection: imageValueCollection,
  description: "gee_nfpors",
  folder: "GEE_Exports",
  fileFormat: "CSV"
});

