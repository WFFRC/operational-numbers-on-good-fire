// https://code.earthengine.google.com/d0951ded7d62970287f8af1bf1c6d0a7



////////////////////
// This script combines multiple Good Fire steps and allows it to be summarized and exported easily for various datasets

// It does the following:
// -reclassifies the Fire Regime Groups layer into low/mix & high/replacement
// -generates an annual conservative forest mask for the year before each fire
// -reads in bias corrected cbi (CBI_bc) generated annually in the year of each fire by script 'a01_generate_gf_cbi'
// -exports summaries of the data for the summarizing features imported in "Summarizing Features"


////////////////
//// USER-SET DATA
////////////////

//Folder in Google Drive for export CSVs
var exportFolder = 'GEE_Exports';

// The raw fire perimeters uploaded by the user
var firesRaw = ee.FeatureCollection("users/tymc5571/goodfire_dataset_for_analysis_2010_2020");
print('fraw:', firesRaw.limit(10));

var startYear = 2010; //this is the earliest fire year in the dataset
//var startYear = 1990; //this is the earliest fire year in the dataset
var endYear = 2020; //this is the latest fire year in the dataset

// The CBIbc output from the previous script
var gfCBI = ee.Image("users/tymc5571/goodFire_all_cbi_bc_2010_2020"); // data from 01_generate_gf_cbi
//var gfCBI = ee.Image("users/tymc5571/goodFire_all_cbi_bc_1990_2020"); // data from 01_generate_gf_cbi


// SUMMARIZING FEATURES - SET YOUR SUMMARIZING FEATURES HERE

var states = ee.FeatureCollection('TIGER/2018/States'); // US states feature collection for western US CBI
var summarizeFeatures = states.filter(ee.Filter.inList('NAME', ['Washington', 'Oregon', 'California', 'Idaho', 'Nevada', 'Montana',
  'Wyoming', 'Utah', 'Colorado', 'Arizona', 'New Mexico']));
var summarizeName = 'states';


// var sparkCounties = ee.FeatureCollection("users/tymc5571/spark_counties");
// var sparkEcoregions = ee.FeatureCollection("users/tymc5571/spark_l4_ecoregions");
// var sparkWatersheds = ee.FeatureCollection("users/tymc5571/spark_watersheds");

// var summarizeFeatures = sparkCounties;
// var summarizeName = "sparkCounties";

// var summarizeFeatures = sparkEcoregions;
// var summarizeName = "sparkEcoregions";

// var summarizeFeatures = sparkWatersheds;
// var summarizeName = "sparkWatersheds";



//////////////////
//// STABLE SCRIPT DATA
//////////////////

var lcms = ee.ImageCollection("USFS/GTAC/LCMS/v2022-8"); // LCMS for conservative forest layer
var lcpri = ee.ImageCollection("projects/sat-io/open-datasets/LCMAP/LCPRI"); // LCMAP for conservative forest layer
var frg = ee.ImageCollection("LANDFIRE/Fire/FRG/v1_2_0"); // Fire Regime Groups
var states = ee.FeatureCollection('TIGER/2018/States'); // US states feature collection for western US CBI


var uniqueYears = ee.List.sequence(startYear, endYear).map(function(year){
 return ee.Number(year).format().slice(0, -2);  
});
var nYears = ee.Number(uniqueYears.length());

print('You have stated that the polygon set used to generate your CBI contained fires from', nYears, 'years. Those years are: ', uniqueYears);


//// AOI

// Names of the 11 western US states
var westernStatesNames = [
  'Washington', 'Oregon', 'California', 'Idaho', 'Nevada', 'Montana',
  'Wyoming', 'Utah', 'Colorado', 'Arizona', 'New Mexico'
];

// Filter the feature collection to include only the 11 western states
var westernStates = states.filter(ee.Filter.inList('NAME', westernStatesNames));


/////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////
///////////             FIRE REGIME GROUP MASKS                 /////////////////
/////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////


// Reclass FRG data to low/mixed (1) vs. replacement (2) vs. masked (3)
var frgCONUS = frg.filterMetadata('system:index','contains','CONUS').first();
var frgRcl = ee.Image(frgCONUS.remap([1,2,3,4,5,111,112,131,132,133],[1,2,1,2,2,3,3,3,3,3],0,'FRG')).rename('frcRcls');
var frgLowMix = ee.Image(frgRcl.eq(1)).rename('frgLowMix').selfMask();
var frgReplace = ee.Image(frgRcl.eq(2)).rename('frgReplace').selfMask();


/////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////
///////////       GENERATE ANNUAL CONSERVATIVE FOREST MASK      /////////////////
/////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////


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
    var andResult = ee.Image(image1.and(image2)).rename(andName);
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

// Operate
var forestStartYear = ee.Number(startYear).subtract(1);

var lcpriCoverConus = lcpri.filter(ee.Filter.date(forestStartYear.format('%d'), ee.Number(endYear).format('%d')));
var lcmsCoverConus = lcms.filter(ee.Filter.eq('study_area', 'CONUS')).filter(ee.Filter.date(forestStartYear.format('%d'), ee.Number(endYear).format('%d'))).select('Land_Cover');

var lcpriFor = lcpriCoverConus.map(reclassifyImageBinary(4));
var lcmsFor = lcmsCoverConus.map(reclassifyImageBinary(1));

var conservativeForest = combineCollectionsWithAnd(lcpriFor, lcmsFor, 'conservativeForest').map(addYearProperty);



/////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////
///////////             Manage GF CBI FROM SCRIPT 1             /////////////////
/////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////


print('FRG proj:', frgRcl.projection());
print('forest proj:', conservativeForest.first().projection());

// Get the band names from the image
var bandNames = gfCBI.bandNames();

// Create an ImageCollection from the bands
var cbiCollection = ee.ImageCollection(bandNames.map(function(bandName) {
  var yr = ee.String(bandName).split('_').get(1);
  return gfCBI.select([bandName]).rename('cbi_bc').set('year', yr);
}));

print('CBI proj', cbiCollection.first().projection());

// // Reproject to match other data
// var cbiCollection = cbiCollection.map(function(im) {
//   var imReproj = im.reproject({
//     crs: frgRcl.projection().wkt(),
//     scale: frgRcl.projection().nominalScale()
//   });
//   return(imReproj);
// });

// print('New CBI proj', cbiCollection.first().projection());




/////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////
///////////             GENERATE ANNUAL GF IMAGES                 ///////////////
/////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////


var generateGoodFireImage = function(thisYear) {
  var thisYearCBI = ee.Image(cbiCollection.filter(ee.Filter.eq('year', thisYear)).first().select('cbi_bc'));
  var yearPriorForest = ee.Image(conservativeForest.filter(ee.Filter.eq('year', ee.Number.parse(thisYear).subtract(1))).first()).rename('yearPriorForest');
  
  var cbiForest = thisYearCBI.updateMask(yearPriorForest);
  var cbiLowMod = cbiForest.lt(2.25).and(cbiForest.gte(0.1)).rename('cbiLower').multiply(ee.Image.pixelArea()).selfMask();
  var cbiHigh = cbiForest.gte(2.25).rename('cbiHigh').multiply(ee.Image.pixelArea()).selfMask();
  var cbiAnyBurned = cbiForest.gte(0.1).rename('cbiAnyBurned').multiply(ee.Image.pixelArea()).selfMask();
  var cbiUnburned = cbiForest.lt(0.1).and(cbiForest.gte(0)).rename('cbiUnburned').multiply(ee.Image.pixelArea()).selfMask();
  
  var frgLowCbiLow = cbiLowMod.updateMask(frgLowMix).rename('lowerGoodFire');
  var frgReplaceCbiHigh = cbiHigh.updateMask(frgReplace).rename('highGoodFire');
  var frgLowCbiHigh = cbiHigh.updateMask(frgLowMix).rename('lowerRegimeCbiHigh');
  var frgReplaceCbiLow = cbiLowMod.updateMask(frgReplace).rename('replaceRegimeCbiLow');
  var frgLowCbiUnburned = cbiUnburned.updateMask(frgLowMix).rename('lowerRegimeCbiUnburned');
  var frgReplaceCbiUnburned = cbiUnburned.updateMask(frgReplace).rename('replaceRegimeCbiUnburned');
  var forestArea = yearPriorForest.multiply(ee.Image.pixelArea()).selfMask();
  var totArea = ee.Image.pixelArea().rename('totalArea');
  
  
  var allGF = frgLowCbiLow.addBands(frgReplaceCbiHigh)
                          .addBands(frgLowCbiHigh)
                          .addBands(frgReplaceCbiLow)
                          .addBands(frgLowCbiUnburned)
                          .addBands(frgReplaceCbiUnburned)
                          .addBands(cbiLowMod)
                          .addBands(cbiHigh)
                          .addBands(cbiUnburned)
                          .addBands(cbiAnyBurned)
                          .addBands(forestArea)
                          .addBands(totArea)
                          .set('year', thisYear);

  return(allGF);
};

var allGF = ee.ImageCollection(uniqueYears.map(generateGoodFireImage));
print('AllGF:', allGF);



//////////////////
//// Visualize to check data
//////////////////

// Generation layers
Map.addLayer(frgLowMix, {min: 0, max: 1, palette: ['black', 'yellow']}, 'FRG LowMix');
Map.addLayer(frgReplace, {min: 0, max: 1, palette: ['black', 'red']}, 'FRG High');
Map.addLayer(ee.Image(conservativeForest.first()), {min: 0, max: 1, palette: ['black', 'limegreen']}, 'conservative forest 2009');
var CBIpaletteclass = ["#0000CD","#6B8E23", "#FFFF00","#FFA500","#FF0000" ]; 
Map.addLayer(cbiCollection.first(),    {min:0, max:3, palette:CBIpaletteclass}, 'CBI 2010');
Map.addLayer(cbiCollection.mosaic(), {min:0, max:3, palette:CBIpaletteclass}, 'CBI all');


// Output layers
Map.addLayer(allGF.first().select('lowerGoodFire'), {min: 0, max: 1, palette: ['white', 'springgreen']}, 'Lower Good Fire 2010');
Map.addLayer(allGF.select('lowerGoodFire').mosaic(), {min: 0, max: 1, palette: ['white', 'springgreen']}, 'Lower Good Fire All');

Map.addLayer(allGF.first().select('highGoodFire'), {min: 0, max: 1, palette: ['white', 'greenyellow']}, 'High Good Fire 2010');
Map.addLayer(allGF.select('highGoodFire').mosaic(), {min: 0, max: 1, palette: ['white', 'greenyellow']}, 'High Good Fire All');

Map.addLayer(allGF.first().select('lowerRegimeCbiHigh'), {min: 0, max: 1, palette: ['white', 'hotpink']}, 'Too Hot 2010');
Map.addLayer(allGF.first().select('replaceRegimeCbiLow'), {min: 0, max: 1, palette: ['white', 'plum']}, 'Too Low 2010');



/////////////////
//// Export summaries
/////////////////



// //Feature attributes to export
// var selectors = summarizeIdentifiers.cat(['lowerGoodFire', 
//                                           'highGoodFire',
//                                           'lowerRegimeCbiHigh',
//                                           'replaceRegimeCbiLow',
//                                           'lowerRegimeCbiUnburned',
//                                           'replaceRegimeCbiUnburned',
//                                           'cbiLower',
//                                           'cbiHigh',
//                                           'cbiAnyBurned',
//                                           'cbiUnburned',
//                                           'yearPriorForest',
//                                           'totalArea',
//                                           'year',
//                                           'units']);








// var runYear = function(year) {
//     var img = ee.Image(allGF.filter(ee.Filter.eq('year', year)).first());

//     // Reduction options: forested area
//     var mappedReduction = summarizeFeatures.map(function(feature) {
//       var datFeature = feature.set(img.reduceRegion({
//         reducer: ee.Reducer.sum(),
//         geometry: feature.geometry(),
//         scale: 30,
//         tileScale: 16,
//         maxPixels: 1e13,
//       }));
      
//       return datFeature.set('year', year)
//                       .set('units', 'm^2')
//                       .setGeometry(null);
//     });

//     return(mappedReduction.flatten());
// };

// var allDats = ee.FeatureCollection(uniqueYears.map(runYear)
//                                               .flatten());


// // Export the combined table
// Export.table.toDrive({
//   collection: allDats,
//   description: 'combined_gf_data_' + summarizeName,
//   fileNamePrefix: 'combined_gf_data_' + summarizeName,
//   folder: 'GEE_Exports',
//   fileFormat: 'CSV',sl
// });











// DEPRECATED
// Iterate over each year, process the data, and set up the export
for (var year = startYear; year <= endYear; year++) {
  (function(year) { // Start  Immediately Invoked Function Expression (IIFE) to capture the current year
    // Filter the image collection for the specific year
    
    var img = ee.Image(allGF.filter(ee.Filter.eq('year', ee.Number(year).format())).first());

    // Reduction options: forested area
    var mappedReduction = summarizeFeatures.map(function(feature) {
      return feature.set(img.reduceRegion({
        reducer: ee.Reducer.sum(),
        geometry: feature.geometry(),
        scale: 30,
        tileScale: 16,
        maxPixels: 1e11,
      }));
    });

    // Add the year as a property for each feature in the summary
    mappedReduction = mappedReduction.map(function(feature) {
      return feature.set('year', year)
                    .set('units', 'm^2')
                    .setGeometry(null);
    });

    // Export task setup
    Export.table.toDrive({
      collection: mappedReduction,
      description: 'gf_data_' + year + '_' + summarizeName,
      fileNamePrefix: 'gf_data_' + year + '_' + summarizeName,
      folder: exportFolder,
      fileFormat: 'CSV'
    });
  })(year); // End IIFE and invoke with current year
}





// FIRE FEATURE LEVEL

//print('test', ee.Number(firesRaw.first().get('Fire_Year')).format().slice(0, -2))

var gfReduceFeature = function(f) {
  
  var fYr = ee.Number(f.get('Fire_Year')).format().slice(0, -2);
  var yrImg = ee.Image(allGF.filter(ee.Filter.eq('year', fYr)).first());

  var fullDatsF = f.set(yrImg.reduceRegion({
    reducer: ee.Reducer.sum(),
    geometry: f.geometry(),
    scale: 30,
    tileScale: 16,
    maxPixels: 1e11
  }));
  
  return(fullDatsF.setGeometry(null));
};


var fullDatsFires = firesRaw.map(gfReduceFeature);

//print(fullDatsFires.limit(10))

Export.table.toDrive({
  collection: fullDatsFires,
  description: 'gf_data_fire_events_' + startYear + '_' + endYear,
  fileNamePrefix: 'gf_data_fire_events_' + startYear + '_' + endYear,
  folder: exportFolder,
  fileFormat: 'CSV'
});

