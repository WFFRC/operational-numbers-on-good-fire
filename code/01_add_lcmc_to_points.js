//This code is meant to be run on Google Earth Engine
//code link: https://code.earthengine.google.com/0279a285caa496ae638011c358c75f08

var lcms = ee.ImageCollection("USFS/GTAC/LCMS/v2022-8"),
    nfpors = ee.FeatureCollection("users/tymc5571/West_NFPORS_2010_2021");

print("NFPORS", nfpors.limit(50));

// Filter the LCMS by image name containing "LCMS_CONUS",
// to only include the Land Cover band, and to include the dates of interest
var lcmsInterest = lcms.filter(ee.Filter.stringContains('system:index', 'LCMS_CONUS')).select("Land_Cover").filterDate('2010-01-01', '2021-12-31');

print(lcmsInterest);


// Create a function to apply to each image in the ImageCollection
var addImageValues = function(image) {
  var imageDate = image.date().format('YYYY'); // Get the image year
  var properties = image.reduceRegions({
    collection: nfpors,
    reducer: ee.Reducer.mean().setOutputs(["LandCover"]), //reduce and set output name to landcover
    scale: 30, 
    crs: image.projection() // Match the projection of the image
  });

  // Rename the properties to include the image date as a property
  var renamedProperties = properties.map(function(feature) {
    return feature.set('Year', ee.String(imageDate));
  });

  return renamedProperties;
};

// Apply the addImageValues function to each image in the ImageCollection
var imageValueCollection = lcmsInterest.map(addImageValues).flatten();

// Print the resulting FeatureCollection
print(imageValueCollection.limit(50));

print(imageValueCollection.size());

//Export
Export.table.toDrive({
  collection: imageValueCollection,
  description: "LCMS_nfpors",
  folder: "GEE_Exports",
  fileFormat: "CSV"
});

