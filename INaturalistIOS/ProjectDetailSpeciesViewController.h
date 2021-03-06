//
//  ProjectDetailSpeciesViewController.h
//  iNaturalist
//
//  Created by Alex Shepard on 2/23/16.
//  Copyright © 2016 iNaturalist. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "ProjectDetailV2ViewController.h"

@interface ProjectDetailSpeciesViewController : UITableViewController

@property (assign) NSInteger totalCount;
@property NSArray *speciesCounts;
@property BOOL hasFetchedSpecies;

@property (assign) id <ProjectDetailV2Delegate> projectDetailDelegate;

- (void)reloadDataViews;

@end
