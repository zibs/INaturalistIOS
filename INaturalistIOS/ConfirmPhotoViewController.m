//
//  ConfirmPhotoViewController.m
//  iNaturalist
//
//  Created by Alex Shepard on 2/25/15.
//  Copyright (c) 2015 iNaturalist. All rights reserved.
//

#import <MBProgressHUD/MBProgressHUD.h>
#import <CoreLocation/CoreLocation.h>
#import <BlocksKit/BlocksKit.h>
#import <BlocksKit/BlocksKit+UIKit.h>
#import <FontAwesomeKit/FAKFontAwesome.h>
#import <Photos/Photos.h>
#import <M13ProgressSuite/M13ProgressViewPie.h>

#import "ConfirmPhotoViewController.h"
#import "Taxon.h"
#import "TaxonPhoto.h"
#import "ImageStore.h"
#import "Observation.h"
#import "ObservationPhoto.h"
#import "MultiImageView.h"
#import "TaxaSearchViewController.h"
#import "UIColor+ExploreColors.h"
#import "Observation.h"
#import "Analytics.h"
#import "Project.h"
#import "ProjectObservation.h"
#import "ObsEditV2ViewController.h"
#import "UIColor+INaturalist.h"
#import "INaturalistAppDelegate.h"
#import "CLLocation+EXIFGPSDictionary.h"
#import "UIImage+INaturalist.h"
#import "NSData+INaturalist.h"
#import "UIViewController+INaturalist.h"

#define CHICLETWIDTH 100.0f
#define CHICLETHEIGHT 98.0f
#define CHICLETPADDING 2.0

@interface ConfirmPhotoViewController () {
    PHPhotoLibrary *phLib;
    UIButton *retake, *confirm;
}
@property NSArray *iconicTaxa;
@property NSMutableArray *downloadedImages;
@property (copy) CLLocation *obsLocation;
@property (copy) NSDate *obsDate;
@property CLLocationManager *locationManager;
@end

@implementation ConfirmPhotoViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor blackColor];
    
    // fetch location to insert into image exif when we save it
    self.locationManager = [[CLLocationManager alloc] init];
    [self.locationManager startUpdatingLocation];
    
    self.downloadedImages = [NSMutableArray array];
    
    if (!self.confirmFollowUpAction) {
        __weak typeof(self) weakSelf = self;
        self.confirmFollowUpAction = ^(NSArray *confirmedImages){
            __strong typeof(weakSelf) strongSelf = weakSelf;
            
            // go straight to making the observation
            Observation *o = [Observation object];
            o.localCreatedAt = [NSDate date];
            o.localUpdatedAt = [NSDate date];
            
            if (strongSelf.obsLocation) {
                o.latitude = @(strongSelf.obsLocation.coordinate.latitude);
                o.longitude = @(strongSelf.obsLocation.coordinate.longitude);
                o.positionalAccuracy = @(strongSelf.obsLocation.horizontalAccuracy);
            }
            
            if (strongSelf.obsDate) {
                o.observedOn = strongSelf.obsDate;
                o.localObservedOn = o.observedOn;
                o.observedOnString = [Observation.jsDateFormatter stringFromDate:o.localObservedOn];
            }
            
            if (weakSelf.taxon) {
                o.taxon = weakSelf.taxon;
                o.speciesGuess = weakSelf.taxon.defaultName ?: weakSelf.taxon.name;
            }
            
            if (weakSelf.project) {
                ProjectObservation *po = [ProjectObservation object];
                po.observation = o;
                po.project = weakSelf.project;
            }
            
            NSInteger idx = 0;
            for (UIImage *image in confirmedImages) {
                ObservationPhoto *op = [ObservationPhoto object];
                op.position = @(idx);
                [op setObservation:o];
                [op setPhotoKey:[ImageStore.sharedImageStore createKey]];
                
                NSError *saveError = nil;
                BOOL saved = [[ImageStore sharedImageStore] storeImage:image
                                                                forKey:op.photoKey
                                                                 error:&saveError];
                if (saveError) {
                    [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Photo Save Error", @"Title for photo save error alert msg")
                                                message:saveError.localizedDescription
                                               delegate:nil
                                      cancelButtonTitle:NSLocalizedString(@"OK", nil)
                                      otherButtonTitles:nil] show];
                    [o destroy];
                    [op destroy];
                    return;
                } else if (!saved) {
                    [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Photo Save Error", @"Title for photo save error alert msg")
                                                message:NSLocalizedString(@"Unknown error", @"Message body when we don't know the error")
                                               delegate:nil
                                      cancelButtonTitle:NSLocalizedString(@"OK", nil)
                                      otherButtonTitles:nil] show];
                    [o destroy];
                    [op destroy];
                    return;
                }
                
                op.localCreatedAt = [NSDate date];
                op.localUpdatedAt = [NSDate date];

                idx++;
            }
            
            ObsEditV2ViewController *editObs = [[ObsEditV2ViewController alloc] initWithNibName:nil bundle:nil];
            editObs.observation = o;
            editObs.shouldContinueUpdatingLocation = strongSelf.shouldContinueUpdatingLocation;
            editObs.isMakingNewObservation = YES;
            
            // for sizzle
            INaturalistAppDelegate *appDelegate = (INaturalistAppDelegate *)[[UIApplication sharedApplication] delegate];
            [strongSelf.navigationController setDelegate:appDelegate];
            
            [strongSelf.navigationController setNavigationBarHidden:NO animated:YES];
            [strongSelf.navigationController pushViewController:editObs animated:YES];
        };
    }
    
    phLib = [PHPhotoLibrary sharedPhotoLibrary];
    
    self.multiImageView = ({
        MultiImageView *iv = [[MultiImageView alloc] initWithFrame:CGRectZero];
        iv.translatesAutoresizingMaskIntoConstraints = NO;
        
        iv.borderColor = [UIColor lightGrayColor];
        iv.pieBorderWidth = 4.0f;
        iv.pieColor = [UIColor lightGrayColor];
        
        iv;
    });
    [self.view addSubview:self.multiImageView];
    
    retake = ({
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.frame = CGRectZero;
        button.translatesAutoresizingMaskIntoConstraints = NO;
        
        button.tintColor = [UIColor whiteColor];
        button.backgroundColor = [UIColor grayColor];
        
        button.layer.borderColor = [UIColor blackColor].CGColor;
        button.layer.borderWidth = 0.5f;
        
        [button setTitle:NSLocalizedString(@"RETAKE", @"Retake a photo")
                forState:UIControlStateNormal];
        button.titleLabel.textAlignment = NSTextAlignmentCenter;
        button.titleLabel.font = [UIFont boldSystemFontOfSize:15.0f];
        
        
        __weak typeof(self)weakSelf = self;
        [button bk_addEventHandler:^(id sender) {
            __strong typeof(weakSelf)strongSelf = weakSelf;
            [[Analytics sharedClient] event:kAnalyticsEventNewObservationRetakePhotos];
            [strongSelf.navigationController popViewControllerAnimated:YES];
        } forControlEvents:UIControlEventTouchUpInside];
        
        button;
    });
    [self.view addSubview:retake];
    
    confirm = ({
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.frame = CGRectZero;
        button.translatesAutoresizingMaskIntoConstraints = NO;
        
        button.tintColor = [UIColor whiteColor];
        button.backgroundColor = [UIColor inatGreen];
        
        button.layer.borderColor = [UIColor blackColor].CGColor;
        button.layer.borderWidth = 0.5f;
        
        [button setTitle:NSLocalizedString(@"NEXT", @"Confirm a new photo")
                forState:UIControlStateNormal];
        button.titleLabel.textAlignment = NSTextAlignmentCenter;
        button.titleLabel.font = [UIFont boldSystemFontOfSize:15.0f];
        
        [button addTarget:self
                   action:@selector(confirm)
         forControlEvents:UIControlEventTouchUpInside];
        
        button.enabled = NO;
        
        button;
    });
    [self.view addSubview:confirm];
    
    UILayoutGuide *safeGuide = [self inat_safeLayoutGuide];

    // horizontal
    [self.multiImageView.leadingAnchor constraintEqualToAnchor:safeGuide.leadingAnchor].active = YES;
    [self.multiImageView.trailingAnchor constraintEqualToAnchor:safeGuide.trailingAnchor].active = YES;
    
    [retake.leadingAnchor constraintEqualToAnchor:safeGuide.leadingAnchor].active = YES;
    [retake.trailingAnchor constraintEqualToAnchor:confirm.leadingAnchor].active = YES;
    [confirm.trailingAnchor constraintEqualToAnchor:safeGuide.trailingAnchor].active = YES;
    
    [retake.widthAnchor constraintEqualToAnchor:confirm.widthAnchor].active = YES;
    
    // vertical
    [self.multiImageView.topAnchor constraintEqualToAnchor:safeGuide.topAnchor].active = YES;
    [self.multiImageView.bottomAnchor constraintEqualToAnchor:confirm.topAnchor].active = YES;
    
    [confirm.bottomAnchor constraintEqualToAnchor:safeGuide.bottomAnchor].active = YES;
    [retake.bottomAnchor constraintEqualToAnchor:safeGuide.bottomAnchor].active = YES;
    
    [confirm.heightAnchor constraintEqualToConstant:48.0f].active = YES;
    [retake.heightAnchor constraintEqualToConstant:48.0f].active = YES;
}

- (void)confirm {
    // make sure we have permission to the photo library
    switch ([PHPhotoLibrary authorizationStatus]) {
        case PHAuthorizationStatusDenied:
        case PHAuthorizationStatusRestricted: {
            // don't notify, don't try to save photo
            dispatch_async(dispatch_get_main_queue(), ^{
                [self moveOnToSaveNewObservation];
            });
            break;
        }
        case PHAuthorizationStatusNotDetermined:
            // ask permission
            [self requestPhotoLibraryPermission];
            break;
        case PHAuthorizationStatusAuthorized: {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self savePhotoAndMoveOn];
            });
            break;
        }
        default:
            break;
    }
}

- (void)requestPhotoLibraryPermission {
    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
        [[Analytics sharedClient] event:kAnalyticsEventPhotoLibraryPermissionsChanged
                         withProperties:@{
                                          @"Via": NSStringFromClass(self.class),
                                          @"NewValue": @(status),
                                          }];
        switch (status) {
            case PHAuthorizationStatusDenied:
            case PHAuthorizationStatusRestricted:
            case PHAuthorizationStatusNotDetermined: {
                // don't notify, don't try to save photo
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self moveOnToSaveNewObservation];
                });
                break;
            }
            case PHAuthorizationStatusAuthorized: {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self savePhotoAndMoveOn];
                });
                break;
            }
            default:
                break;
        }
    }];
    
}

- (void)moveOnToSaveNewObservation {
    if ([self isSelectingFromLibrary]) {
        if (self.photoTakenLocation) {
            self.obsLocation = self.photoTakenLocation;
        }
        if (self.photoTakenDate) {
            self.obsDate = self.photoTakenDate;
        }
    } else {
        self.obsLocation = self.locationManager.location;
        self.obsDate = [NSDate date];
    }
    
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self.confirmFollowUpAction(self.downloadedImages ?: @[ self.image ]);
    });
}

- (void)savePhotoAndMoveOn {
    [[Analytics sharedClient] event:kAnalyticsEventNewObservationConfirmPhotos];
    
    // this can take a moment, so hide the retake/confirm buttons
    confirm.hidden = YES;
    retake.hidden = YES;
    
    if (self.isSelectingFromLibrary) {
        // can proceed directly to followup
        [self moveOnToSaveNewObservation];
    } else {
        // we need to save to the Photos library
        MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
        hud.labelText = NSLocalizedString(@"Saving new photo...", @"status while saving your image");
        hud.removeFromSuperViewOnHide = YES;
        hud.dimBackground = YES;
        
        // build the metadata dictionary, with GPS if available
        NSMutableDictionary *mutableMetadata = [self.metadata mutableCopy];
        if (self.locationManager && self.locationManager.location) {
            // update the provided GPSDictionary with values from the location manager
            NSMutableDictionary *gpsDictionary = [[mutableMetadata objectForKey:(NSString *)kCGImagePropertyGPSDictionary] mutableCopy];
            if (!gpsDictionary) {
                gpsDictionary = [NSMutableDictionary dictionary];
            }
            [gpsDictionary setValuesForKeysWithDictionary:[self.locationManager.location inat_GPSDictionary]];
            mutableMetadata[(NSString *)kCGImagePropertyGPSDictionary] = gpsDictionary;
        }
        
        // convert the UIImage into an NSData object, with the metadata included
        // including GPS if we added it in the previous step
        NSData *imageData = [self.image inat_JPEGDataRepresentationWithMetadata:[NSDictionary dictionaryWithDictionary:mutableMetadata]];
        
        [phLib performChanges:^{
            PHAssetCreationRequest *request = [PHAssetCreationRequest creationRequestForAsset];
            [request addResourceWithType:PHAssetResourceTypePhoto data:imageData options:nil];
            
            // this updates the iOS photos database but not EXIF
            if (self.locationManager) {
                request.location = self.locationManager.location;
            }
            request.creationDate = [NSDate date];
        } completionHandler:^(BOOL success, NSError * _Nullable error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [MBProgressHUD hideAllHUDsForView:self.view animated:YES];
                
                if (error) {
                    [[Analytics sharedClient] debugLog:[NSString stringWithFormat:@"error saving image: %@",
                                                        error.localizedDescription]];
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Error Saving Image", @"image save error title")
                                                                                   message:error.localizedDescription
                                                                            preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK",nil)
                                                              style:UIAlertActionStyleCancel
                                                            handler:nil]];
                    [self presentViewController:alert animated:YES completion:nil];
                } else {
                    if (success) {
                        [self moveOnToSaveNewObservation];
                    }
                }
            });

        }];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    if (self.image) {
        self.multiImageView.imageCount = 1;
        UIImageView *iv = [[self.multiImageView imageViews] firstObject];
        iv.image = self.image;
        iv.contentMode = UIViewContentModeScaleAspectFit;
        [self.downloadedImages addObject:self.image];
        [self configureNextButton];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    [self.navigationController setNavigationBarHidden:YES animated:NO];
    [self.navigationController setToolbarHidden:YES animated:NO];
    
}

- (void)configureNextButton {
    if (self.image) {
        confirm.enabled = YES;
    } else {
        confirm.enabled = NO;
    }
}

@end
