//Tyler L. McIntosh, Earth Lab, 2024


//////////////////
//// DATA
//////////////////


var lcms = ee.ImageCollection("USFS/GTAC/LCMS/v2022-8");
var lcpri = ee.ImageCollection("projects/sat-io/open-datasets/LCMAP/LCPRI");


// Names of the 11 western US states
var westernStatesNames = [
  'Washington', 'Oregon', 'California', 'Idaho', 'Nevada', 'Montana',
  'Wyoming', 'Utah', 'Colorado', 'Arizona', 'New Mexico'
];

// Load US states feature collection
var states = ee.FeatureCollection('TIGER/2018/States');

// Filter the feature collection to include only the 11 western states
var westernStates = states.filter(ee.Filter.inList('NAME', westernStatesNames));


////////////////////////////
///// FUNCTIONS
////////////////////////////


// A general function to reclassify an image and mask it such that values of 'value' are equal to 1
// This version copies the system:time_start property from the original image.
var reclassifyImageBinary = function(value) {
  return function(image) {
    var binaryImage = image.eq(value).selfMask();
    // Preserve the original image's date property
    return binaryImage.copyProperties(image, ['system:time_start']);
  };
};

// Function to apply 'and' operation between corresponding images of two collections
// This version copies the system:time_start property from the first image.
function combineCollectionsWithAnd(collection1, collection2, andName) {
  // Convert collection2 to a list once for efficiency
  var list2 = collection2.toList(collection2.size());

  // Combine the two collections into a list of image pairs
  var list1 = collection1.toList(collection1.size());
  var combinedList = list1.zip(list2);

  // Map a function over the list to apply the 'and' operation to each image pair
  var combinedCollection = ee.ImageCollection(combinedList.map(function(pair) {
    var image1 = ee.Image(ee.List(pair).get(0));
    var image2 = ee.Image(ee.List(pair).get(1));
    // Perform the 'and' operation and rename the resulting image
    var andResult = image1.and(image2).rename(andName);
    // Preserve the system:time_start property from the first image
    return andResult.copyProperties(image1, ['system:time_start']);
  }));

  return combinedCollection;
}

// Function to add a year property to each image
function addYearProperty(image, startYear) {
  var year = image.date().get('year');
  return image.set('year', year);
}



print('lcms', lcms);
print('lcmap', lcpri);

var lcpriCoverConus = lcpri.filter(ee.Filter.date('1985', '2022'));
var lcmsCoverConus = lcms.filter(ee.Filter.eq('study_area', 'CONUS')).filter(ee.Filter.date('1985', '2022')).select('Land_Cover');

print('filt lcmap', lcpriCoverConus);
print('filt lcms', lcmsCoverConus);

var lcpriFor = lcpriCoverConus.map(reclassifyImageBinary(4));
var lcmsFor = lcmsCoverConus.map(reclassifyImageBinary(1));

print("LCMAP forest", lcpriFor);
print("LCMS forest", lcmsFor);


var conservativeFor = combineCollectionsWithAnd(lcpriFor, lcmsFor, 'conservativeForest').map(addYearProperty);
var conservForTest = ee.Image(conservativeFor.filter(ee.Filter.date('2020', '2021')).first());
print('conservative forest', conservativeFor);
print('conservative forest test', conservForTest);
Map.addLayer(conservForTest, {min: 0, max: 1, palette: ['black', 'red']}, 'conservative forest');


// //reduction options: forested area
// var mappedReduction=westernStates.map(function(feature){
//   return feature.set(conservForTest.reduceRegion({
//     reducer:ee.Reducer.sum(),
//     geometry: feature.geometry(),
//     scale: 30,
//     tileScale: 16,
//     maxPixels: 1e13,
//   }));
// });



// // export
// var exported = mappedReduction.select(['.*'], null, false);
// Export.table.toDrive({
//   collection:exported,
//   description:'forest_TLM_2020',
//   fileFormat:'CSV'
// });


// Define the start and end years
var startYear = 1985;
var endYear = 2021;


// Iterate over each year, process the data, and set up the export
for (var year = startYear; year <= endYear; year++) {
  (function(year) { // Start  Immediately Invoked Function Expression (IIFE) to capture the current year
    // Filter the image collection for the specific year
    var img = ee.Image(conservativeFor.filter(ee.Filter.calendarRange(year, year, 'year')).first());

    // Reduction options: forested area
    var mappedReduction = westernStates.map(function(feature) {
      return feature.set(img.reduceRegion({
        reducer: ee.Reducer.sum(),
        geometry: feature.geometry(),
        scale: 30,
        tileScale: 16,
        maxPixels: 1e13,
      }));
    });

    // Add the year as a property for each feature in the summary
    mappedReduction = mappedReduction.map(function(feature) {
      return feature.set('year', year);
    });

    // Export task setup
    Export.table.toDrive({
      collection: mappedReduction,
      description: 'forest_pixel_count_' + year,
      fileNamePrefix: 'forest_pixel_count_' + year,
      folder: 'GEE_Exports',
      fileFormat: 'CSV'
    });
  })(year); // End IIFE and invoke with current year
}

