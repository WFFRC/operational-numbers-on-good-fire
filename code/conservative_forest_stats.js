var lcms = ee.ImageCollection("USFS/GTAC/LCMS/v2022-8");
var lcpri = ee.ImageCollection("projects/sat-io/open-datasets/LCMAP/LCPRI");
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
function combineCollectionsWithAnd(collection1, collection2) {
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
    var andResult = image1.and(image2).rename('andResult');
    // Preserve the system:time_start property from the first image
    return andResult.copyProperties(image1, ['system:time_start']);
  }));

  return combinedCollection;
}







print('lcms', lcms);
print('lcmap', lcpri);


// // A general function to reclassify an image and mask it such that values of 'value' are equal to 1
// var reclassifyImageBinary = function(value) {
//   return function(image) {
//     var binaryImage = image.eq(value).selfMask();
//     return binaryImage;
//   };
// };

//

var lcpriFor = lcpri.map(reclassifyImageBinary(4));
var lcmsCoverConus = lcms.filter(ee.Filter.eq('study_area', 'CONUS')).filter(ee.Filter.date('1985', '2022')).select('Land_Cover');
var lcmsFor = lcmsCoverConus.map(reclassifyImageBinary(1));

print("LCMAP forest", lcpriFor);
print("LCMS forest", lcmsFor);


var lcpriTest = ee.Image(lcpriFor.first());
Map.addLayer(lcpriTest, {min: 0, max: 1, palette: ['black', 'pink']}, 'lcmapFor');
var lcmsTest = ee.Image(lcmsFor.first());
Map.addLayer(lcmsTest, {min: 0, max: 1, palette: ['black', 'blue']}, 'lcmsFor');




// // Function to apply 'and' operation between corresponding images of two collections
// function combineCollectionsWithAnd(collection1, collection2) {
//   // Ensure both collections have the same number of images
//   var size1 = collection1.size();
//   var size2 = collection2.size();
//   if (size1.getInfo() !== size2.getInfo()) {
//     print('Collections do not have the same number of images.');
//     return null;
//   } else {
//     // Combine the two collections into a list of image pairs
//     var list1 = collection1.toList(size1);
//     var list2 = collection2.toList(size2);
//     var combinedList = list1.zip(list2);

//     // Map a function over the list to apply the 'and' operation to each image pair
//     var combinedCollection = ee.ImageCollection(combinedList.map(function(pair) {
//       var image1 = ee.Image(ee.List(pair).get(0));
//       var image2 = ee.Image(ee.List(pair).get(1));
//       return image1.and(image2).rename('andResult');
//     }));

//     return combinedCollection;
//   }
// }

var conservativeFor = combineCollectionsWithAnd(lcpriFor, lcmsFor);
var conservForTest = ee.Image(conservativeFor.first());
print('conservative forest', conservativeFor);
Map.addLayer(conservForTest, {min: 0, max: 1, palette: ['black', 'red']}, 'conservative forest');






// Names of the 11 western US states
var westernStatesNames = [
  'Washington', 'Oregon', 'California', 'Idaho', 'Nevada', 'Montana',
  'Wyoming', 'Utah', 'Colorado', 'Arizona', 'New Mexico'
];

// Load US states feature collection
var states = ee.FeatureCollection('TIGER/2018/States');

// Filter the feature collection to include only the 11 western states
var westernStates = states.filter(ee.Filter.inList('NAME', westernStatesNames));

// Check the filtered states
print('Western States', westernStates);


// Function to add a year property to each image
function addYearProperty(image, startYear) {
  var year = image.date().get('year');
  return image.set('year', year);
}

// Function to summarize each image for each state
function summarizeImage(image) {
  var stats = image.reduceRegions({
    collection: westernStates,
    reducer: ee.Reducer.count(), // This counts the number of non-masked pixels
    scale: 30 // Assuming a scale of 30 meters, adjust as needed
  });

  // Add the year as a property for each feature in the summary
  var year = image.get('year');
  stats = stats.map(function(feature) {
    return feature.set('year', year);
  });

  return stats;
}

// Apply the addYearProperty function over the collection
var startYear = 1985; // Define the start year if needed
conservativeFor = conservativeFor.map(function(image) {
  return addYearProperty(image, startYear);
});

print(conservativeFor);



////////////////////////////////////////////////////////////////////////

// conservativeFor = conservativeFor.filter(
//   ee.Filter.or(
//     ee.Filter.eq('year', 1985),
//     ee.Filter.eq('year', 1986)
//   )
// );
// print(conservativeFor);





// // Function to process and return the pixel count for a single year as a FeatureCollection
// function processYear(year, conservativeFor, westernStates) {
//   // Filter the image collection for the specific year
//   var yearlyCollection = conservativeFor.filter(ee.Filter.eq('year', year));

//   // Reduce the collection into a single image using the max reducer
//   // to avoid overlapping issues and consider only the presence of pixels through the year
//   var yearlyImage = yearlyCollection.reduce(ee.Reducer.max());

//   // Reduce regions for the single image using westernStates feature collection
//   var yearlyStats = yearlyImage.reduceRegions({
//     collection: westernStates,
//     reducer: ee.Reducer.count(),
//     scale: 30 // Adjust the scale based on your data's resolution
//   });

//   // Map over each feature to set the year property
//   yearlyStats = yearlyStats.map(function(feature) {
//     return feature.set('year', year);
//   });

//   return yearlyStats;
// }

// // Retrieve the list of unique years from the image collection
// var yearsList = ee.List(conservativeFor.aggregate_array('year')).distinct().sort();

// // Map over each year to process and return the yearly stats
// var allYearlyStats = yearsList.map(function(year) {
//   return processYear(year, conservativeFor, westernStates);
// });

// // Combine the yearly stats into a single FeatureCollection
// var combinedStats = ee.FeatureCollection(allYearlyStats).flatten();

// // Print the combined stats to the console
// print('Combined Yearly Stats', combinedStats);




// Define the start and end years
var startYear = 1985;
var endYear = 2021;

// Iterate over each year, process the data, and set up the export
for (var year = startYear; year <= endYear; year++) {
  // Filter the image collection for the specific year
  var yearlyCollection = conservativeFor.filter(ee.Filter.eq('year', year));

  // Reduce the collection into a single image using the max reducer
  var yearlyImage = yearlyCollection.reduce(ee.Reducer.max());

  // Reduce regions for the single image using westernStates feature collection
  var yearlyStats = yearlyImage.reduceRegions({
    collection: westernStates,
    reducer: ee.Reducer.count(),
    scale: 30 // Adjust the scale based on your data's resolution
  }).map(function(feature) {
    return feature.set('year', year);
  });

  
  Export.table.toDrive({
    collection: yearlyStats,
    description: 'Forest_Pixel_Count_for_Year_' + year,
    folder: 'GEE_Exports',
    fileNamePrefix: 'forest_pixel_count_' + year,
    fileFormat: 'CSV'
  });

}







