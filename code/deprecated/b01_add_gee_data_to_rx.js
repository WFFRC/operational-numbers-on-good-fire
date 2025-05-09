
//This code is meant to be run on Google Earth Engine
//code link: https://code.earthengine.google.com/0279a285caa496ae638011c358c75f08


//This code adds land cover and fire regime data to a set of point features input by the user



/////////////// IMPORT & MANAGE DATA ///////////////

// USER-INPUT POINT FEATURES
var nfpors = ee.FeatureCollection("projects/ee-tymc5571-goodfire/assets/West_NFPORS_2010_2021");

// Load fire regime and land cover datasets
var lcpri = ee.ImageCollection("projects/sat-io/open-datasets/LCMAP/LCPRI"),
    lcms = ee.ImageCollection("USFS/GTAC/LCMS/v2022-8"),
    frg = ee.ImageCollection("LANDFIRE/Fire/FRG/v1_2_0");
    
    

print("NFPORS", nfpors.size(), nfpors.limit(50));

// Filter the LCMS & LCMAP by image name containing "LCMS_CONUS",
// to only include the Land Cover band, and to include the dates of interest
var lcmsInterest = lcms.filter(ee.Filter.stringContains('system:index', 'LCMS_CONUS')).select("Land_Cover").filterDate('2009-01-01', '2021-12-31');
var lcpriInterest = lcpri.filterDate('2009-01-01', '2021-12-31');

print('lcms', lcmsInterest);
print('lcmap', lcpriInterest);

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
// And include the date of the image extracted in the property name (e.g. property name: LandCover_2010 if nm = "LandCover")
// (Should be used by mapping over the collection)
// PARAMETERS
// featureCollection: the featureCollection
// imageCollection: the imageCollection
// nm: the name to use in addition to the year to name the new properties, as a string (e.g. "LandCover")
var extractMeanCollectionValuesNamedByYear = function(featureCollection, imageCollection, nm) {
  // Map over each feature in the featureCollection
  return featureCollection.map(function(feature) {
    // Reduce the ImageCollection to accumulate values for each image
    var dict = ee.ImageCollection(imageCollection).iterate(function(image, dict) {
      image = ee.Image(image); // Cast the element of the iteration to an Image
      dict = ee.Dictionary(dict); // Cast the accumulator to a Dictionary

      var imageDate = image.date().format('YYYY'); // Get the image year
      var propName = ee.String(nm).cat('_').cat(imageDate); // Construct property name

      var reducedValue = image.reduceRegion({
        reducer: ee.Reducer.mean(),
        geometry: feature.geometry(),
        scale: 30,
        crs: image.projection() // Match the projection of the image
      });

      // Retrieve the result using the known band name, assuming single-band images
      var meanValue = reducedValue.values().get(0);

      // Update the dictionary with the new data
      return dict.set(propName, meanValue);
    }, ee.Dictionary({}));

    // Set the aggregated results as properties of the feature
    return feature.set(dict);
  });
};

// Function to pull the values from a single image, reduced by mean to a featurecollection
// PARAMETERS
// image: the image to reduce
// collection: the featurecollection to use
// nm: the name of the output property, as a string (e.g. "FRG")

var addMeanImageValues = function(image, collection, nm) {
  // Function to apply reduceRegion to a single feature
  // rather than using reduceRegions for the entire collection.
  // This makes the function more efficient for large collections.
  var reduceSingleFeature = function(feature) {
    var reducedValue = image.reduceRegion({
      reducer: ee.Reducer.mean().setOutputs([nm]),
      geometry: feature.geometry(),
      scale: 30,
      crs: image.projection()
    });
    
    // Set the reduced value as a property of the feature
    return feature.set(reducedValue);
  };

  var reducedCollection = collection.map(reduceSingleFeature);

  return reducedCollection;
};


///////////////// APPLY THE FUNCTIONS & CHECK OUTPUTS ////////////////

var nfporsWithBoth = extractMeanCollectionValuesNamedByYear(nfpors, lcmsInterest, "LandCover_LCMS");
nfporsWithBoth = extractMeanCollectionValuesNamedByYear(nfporsWithBoth, lcpriInterest, "LandCover_LCMAP");
nfporsWithBoth = addMeanImageValues(frcRcl, nfporsWithBoth, "FRG");
print('conservative forest FRG points', nfporsWithBoth.size(), nfporsWithBoth.limit(50));


///////////////////// Export /////////////////////

Export.table.toDrive({
  collection: nfporsWithBoth,
  description: "gee_nfpors_lcms_lcmap",
  folder: "GEE_Exports",
  fileFormat: "CSV"
});

