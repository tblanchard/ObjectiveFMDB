//
//  DBModel.m
//
//  Created by Todd Blanchard on 1/27/16.
//  Copyright © 2017 Todd Blanchard. All rights reserved.
//

#import "DBModel.h"
#import <objc/runtime.h>
#import <Foundation/Foundation.h>
#import "FMDatabase+ObjectiveFMDB.h"
#import "FMResultSet+ObjectiveFMDB.h"
#import "FMDatabaseQueue.h"
#import "SmalltalkCollections.h"
#import "DBModel+DBMigrations.h"

/* Property Introspection
 Value types are store directly.  These types are listed below.
 Object types that are also stored as values include NSString, NSURL, NSUUID, NSData, and NSDate.
 These are stored as TEXT in the database.  It is probably best to just store NSURL and NSUUID as NSString
 in your data object because that's how they are going to come back.  NSDate is handled as a special case.
 
 Relationships...
 If there is a property that references a subclass of DBModel, it is assumed to be a to-one.
 If it is marked readonly - then it is expected that it references the owning object.
 
 */


static NSString * const CharTypeEncoding = @"c";
static NSString * const IntTypeEncoding = @"i";
static NSString * const ShortTypeEncoding = @"s";
static NSString * const LongTypeEncoding = @"l";
static NSString * const LongLongTypeEncoding = @"q";
static NSString * const UnsignedCharTypeEncoding = @"C";
static NSString * const UnsignedIntTypeEncoding = @"I";
static NSString * const UnsignedShortTypeEncoding = @"S";
static NSString * const UnsignedLongTypeEncoding = @"L";
static NSString * const UnsignedLongLongTypeEncoding = @"Q";
static NSString * const FloatTypeEncoding = @"f";
static NSString * const DoubleTypeEncoding = @"d";
static NSString * const BoolTypeEncoding = @"B";
static NSString * const StructTypeEncoding = @"{";

@interface DBPropertyDefinition : NSObject

-initWithName:(NSString*)name property:(objc_property_t)property;

@property (strong, nonatomic) NSString* name;
@property (readonly, getter=isReadOnly) BOOL readOnly;
@property (readonly, getter=isCopy) BOOL copy;
@property (readonly, getter=isRetained) BOOL retained;
@property (readonly, getter=isNonAtomic) BOOL nonAtomic;
@property (readonly) NSString* getterName;
@property (readonly) NSString* setterName;
@property (readonly, getter=isDynamic) BOOL dynamic;
@property (readonly, getter=isWeak) BOOL weak;
@property (strong, nonatomic) NSString* type;
@property (readonly) BOOL isStruct;
@property (strong, nonatomic) NSArray* attributes;

-(NSString*) getPropertyType:(objc_property_t) property;

/*
 R
 The property is read-only (readonly).
 C
 The property is a copy of the value last assigned (copy).
 &
 The property is a reference to the value last assigned (retain).
 N
 The property is non-atomic (nonatomic).
 G<name>
 The property defines a custom getter selector name. The name follows the G (for example, GcustomGetter,).
 S<name>
 The property defines a custom setter selector name. The name follows the S (for example, ScustomSetter:,).
 D
 The property is dynamic (@dynamic).
 W
 The property is a weak reference (__weak).
 P
 The property can be garbage collected
 */

@end

@implementation DBPropertyDefinition

-initWithName:(NSString*)name property:(objc_property_t)property
{
    if(self = [super init])
    {
        self.name = name;
        self.type = [self getPropertyType:property];
        NSString* attributes = [NSString stringWithUTF8String:property_getAttributes(property)];
        self.attributes = [attributes componentsSeparatedByString:@","];
    }
    return self;
}

-(NSString*) getPropertyType:(objc_property_t) property;
{
    const char *attributes = property_getAttributes(property);
    char buffer[1 + strlen(attributes)];
    strcpy(buffer, attributes);
    char *state = buffer, *attribute;
    while ((attribute = strsep(&state, ",")) != NULL)
    {
        if(attribute[0] == 'T' && attribute[1] == '^' && attribute[2] != '@')
        {
            return [NSString stringWithFormat: @"%c*",attribute[2]];
        }
        if(attribute[0] == 'T' && attribute[1] == '{')
        {
            return StructTypeEncoding;
        }
        if (attribute[0] == 'T' && attribute[1] != '@')
        {
            return [[NSString alloc] initWithBytes:attribute + 1 length:strlen(attribute) - 1 encoding:NSASCIIStringEncoding];
        }
        if (attribute[0] == 'T' && attribute[1] == '@' && strlen(attribute) == 2)
        {
            return @"id"; //id type
        }
        else if (attribute[0] == 'T' && attribute[1] == '@')
        {
            return [[NSString alloc] initWithBytes:attribute + 3 length:strlen(attribute) - 4 encoding:NSASCIIStringEncoding];
        }
    }
    
    return @"";
}


-(BOOL)isReadOnly
{
    return [self.attributes indexOfObject:@"R"] != NSNotFound;
}

-(BOOL)isCopy
{
    return [self.attributes indexOfObject:@"C"] != NSNotFound;
}

-(BOOL)isRetained
{
    return [self.attributes indexOfObject:@"&"] != NSNotFound;
}

-(BOOL)isNonAtomic
{
    return [self.attributes indexOfObject:@"N"] != NSNotFound;
}

-(NSString*)getterName
{
    NSString* getter = nil;
    for (NSString* s in self.attributes) {
        if([s hasPrefix:@"G"]) { getter = s; break; }
    }
    if(getter)
    {
        return [getter substringFromIndex:1];
    }
    return [self.attributes[0] substringFromIndex:1];
}

-(NSString*)setterName
{
    NSString* setter = nil;
    for (NSString* s in self.attributes) {
        if([s hasPrefix:@"S"]) { setter = s; break; }
    }
    if(setter)
    {
        return [setter substringFromIndex:1];
    }
    return [@"set" stringByAppendingString:[[self.attributes[0] substringFromIndex:1]capitalizedString]];
}

-(BOOL)isDynamic
{
    return [self.attributes indexOfObject:@"D"] != NSNotFound;
}

-(BOOL)isWeak
{
    return [self.attributes indexOfObject:@"W"] != NSNotFound;
}

-(BOOL)isStrong
{
    return !self.isWeak;
}

-(BOOL)isGarbageCollected
{
    return [self.attributes indexOfObject:@"P"] != NSNotFound;
}

-(NSString*)fieldName
{
    return [self.attributes.lastObject substringFromIndex:1];
}

-(BOOL)isStruct
{
    return [self.attributes.lastObject hasPrefix:@"{"];
}

@end


__strong static NSMutableDictionary* schema;
__strong static NSMutableDictionary* cache;
__strong static FMDatabaseQueue* _queue;
__strong static NSString* _databaseName;

@interface DBModel (PrivateImplementation)

+(BOOL)key:(id)key toWhereClause:(NSString**)wc values:(NSArray**)vs inDatabase:(FMDatabase*)db;
+(NSString*)selectClause;
+(NSString*)orderByClause;
-(NSString*)uniqueIdentifer;

@end

@implementation DBModel

+(NSArray*)fromJsonArray:(NSArray*)array
{
    NSArray* pkNames = [self primaryKeyColumnNames];
    return [array collect:^id(NSDictionary* items) {
        NSDictionary* keys = [items dictionaryWithValuesForKeys:pkNames];
        id object = [self find:keys];
        if(!object)
        {
            // object is not persistent - do not make it so
            object = [self new];
            [object setValuesForKeysWithDictionary:items];
            return object;
        }
        // if object was persistent - save update
        [object setValuesForKeysWithDictionary:items];
        [object save];
        return object;
    }];
}

+(instancetype)fromJsonDictionary:(NSDictionary*)items
{
    NSArray* pkNames = [self primaryKeyColumnNames];
    NSDictionary* keys = [items dictionaryWithValuesForKeys:pkNames];
    id object = [self find:keys];
    if(!object)
    {
        // object is not persistent - do not make it so
        object = [self new];
        [object setValuesForKeysWithDictionary:items];
        return object;
    }
    // if object was persistent - save update
    [object setValuesForKeysWithDictionary:items];
    [object save];
    return object;
}

// mapping from json - transient
+(NSArray*)fromJsonArray:(NSArray*)array inDatabase:(FMDatabase*)db
{
    NSArray* pkNames = [self primaryKeyColumnNamesInDatabase:db];
    return [array collect:^id(NSDictionary* items) {
        NSDictionary* keys = [items dictionaryWithValuesForKeys:pkNames];
        id object = [self find:keys inDatabase:db];
        if(!object)
        {
            object = [self new];
        }
        [object setValuesForKeysWithDictionary:items];
        [object saveInDatabase:db];
        return object;
    }];
}

+(instancetype)fromJsonDictionary:(NSDictionary*)items inDatabase:(FMDatabase*)db
{
    NSArray* pkNames = [self primaryKeyColumnNamesInDatabase:db];
    NSDictionary* keys = [items dictionaryWithValuesForKeys:pkNames];
    id object = [self find:keys inDatabase:db];
    if(!object) { object = [self new]; }
    [object setValuesForKeysWithDictionary:items];
    [object saveInDatabase:db];
    return object;
}


+(void)setDatabaseName:(NSString*)name
{
    if(![name isEqualToString:_databaseName] && _queue)
    {
        [_queue close];
        _queue = nil;
        schema = nil;
        cache = nil;
    }
     _databaseName = name;
}

+(void)closeDatabase
{
    if(_queue)
    {
        [_queue close];
        _queue = nil;
    }
}

+(FMDatabaseQueue*)queue
{
    if(!_queue)
    {
        if(_databaseName)
        {
            NSURL* documentsURL = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
            _queue = [FMDatabaseQueue databaseQueueWithPath:[[documentsURL path]stringByAppendingPathComponent:[_databaseName stringByAppendingString: @".sqlite"]]];
            
            [_queue inTransaction:^(FMDatabase *db, BOOL *rollback) {
                @try {
                    [self performNeededMigrationsInDatabase:db];
                } @catch (NSException *exception) {
                    
                } @finally {
                    
                }
            }];
        }
        else
        {
            [NSException raise:@"No Database Name Specified" format:@"%@ %@ - should have called setDatabaseName:aName first",self,NSStringFromSelector(_cmd)];
        }
    }
    return _queue;
}

// return the database to use for this instance
-(FMDatabaseQueue*)queue
{
    return [[self class]queue];
}

+(NSMapTable*)cache
{
    NSString* classname = NSStringFromClass(self);
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSMutableDictionary new];
    });
    if(!cache[classname])
    {
        cache[classname] = [NSMapTable strongToWeakObjectsMapTable];
    }
    return cache[classname];
}

+(instancetype)cachedObjectForObject:(DBModel*)model
{
    NSMapTable* cache = [[model class] cache];
    NSDictionary* keys = model.primaryKeyValues;
    id cachedObject = [cache objectForKey:keys];
    if(!cachedObject)
    {
        if (cache) [cache setObject: model forKey: keys];
        cachedObject = model;
    }
    return cachedObject;
}

+(instancetype)cachedObjectForDictionary:(NSDictionary*)dict
{
    NSArray* pkNames = [self primaryKeyColumnNames];
    NSDictionary* keys = [dict dictionaryWithValuesForKeys:pkNames];
    NSMapTable* cache = [self cache];
    id cachedObject = [cache objectForKey:keys];
    if(!cachedObject)
    {
        DBModel* model = [[self alloc]init];
        [model setValuesForKeysWithDictionary:dict];
        if (cache) [cache setObject: model forKey: keys];
        cachedObject = model;
    }
    return cachedObject;
}


+(NSMutableDictionary*)schema
{
    if(!schema)
    {
        schema = [NSMutableDictionary new];
    }
    NSMutableDictionary* aSchema = schema[self.tablename];
    if(!aSchema)
    {
        aSchema = [NSMutableDictionary dictionaryWithCapacity:4];
        schema[self.tablename] = aSchema;
    }
    return aSchema;
}

+(NSDictionary*)addToPropertyDefinitions:(NSMutableDictionary*)definitions withPrimaryKeyNames:(NSArray*)keys
{
    if(self == [DBModel class] && [[NSSet setWithArray: keys] isSubsetOfSet:[NSSet setWithArray:[definitions allKeys]]])
    {
        // don't add id
        return definitions;
    }
    
    unsigned int count = 0;
    objc_property_t *properties = class_copyPropertyList(self, &count);
    for(unsigned int i = 0; i < count; ++i)
    {
        NSString* name = [NSString stringWithUTF8String:property_getName(properties[i])];
        DBPropertyDefinition* definition = [[DBPropertyDefinition alloc]initWithName:name property:properties[i]];
        definitions[definition.name] = definition;
    }
    free(properties);
    
    if(self != [DBModel class])
    {
        [[self superclass]addToPropertyDefinitions:definitions withPrimaryKeyNames:keys];
    }
    
    return definitions;
}


+(NSDictionary*)propertyDefinitions
{
    return [self addToPropertyDefinitions:[NSMutableDictionary dictionary] withPrimaryKeyNames:[self primaryKeyPropertyNames]];
}


+(NSArray*)primaryKeyPropertyNames
{
    return @[@"id"];
}

+(NSDictionary*)columnDefinitionsFromProperties
{
    NSDictionary* typeMap = @{
                              CharTypeEncoding:  @"INTEGER",
                              IntTypeEncoding: @"INTEGER",
                              ShortTypeEncoding: @"INTEGER",
                              LongTypeEncoding: @"INTEGER",
                              LongLongTypeEncoding: @"INTEGER",
                              UnsignedCharTypeEncoding: @"INTEGER",
                              UnsignedIntTypeEncoding: @"INTEGER",
                              UnsignedShortTypeEncoding: @"INTEGER",
                              UnsignedLongTypeEncoding: @"INTEGER",
                              UnsignedLongLongTypeEncoding: @"INTEGER",
                              FloatTypeEncoding: @"REAL",
                              DoubleTypeEncoding: @"REAL",
                              BoolTypeEncoding: @"INTEGER",
                              @"NSString": @"TEXT",
                              @"NSMutableString": @"TEXT",
                              @"NSData": @"BLOB",
                              @"NSMutableData": @"BLOB",
                              @"NSDate": @"REAL",
                              @"NSURL": @"TEXT",
                              @"NSUUID" : @"TEXT"
                              };
    
    NSDictionary* properties = [self propertyDefinitions];
    NSMutableDictionary* columns = [NSMutableDictionary dictionaryWithCapacity:properties.count*2];
    
    for(NSString* name in properties)
    {
        DBPropertyDefinition* property = properties[name];
        NSString* type = property.type;
        if(property.isStruct)
        {
            columns[name] = @"BLOB";
        }
        else if(!property.isReadOnly && !property.isDynamic && typeMap[type])
        {
            columns[name] = typeMap[type];
        }
        /* - skipping relationships - I never need them in the phone
         else if([NSClassFromString(property.type) isKindOfClass: [DBModel class]]) // to_one relationship
         {
         NSDictionary* otherProperties = [NSClassFromString(property.type) propertyDefinitions];
         for (NSString* otherName in otherProperties)
         {
         DBPropertyDefinition* otherProperty = otherProperties[otherName];
         // reciprocal relationship
         if([NSClassFromString(otherProperty.type) isKindOfClass: self])
         {
         
         }
         }
         }
         else if([NSClassFromString(propertyType) isKindOfClass: [NSArray class]]) // to_many relationship
         {
         NSDictionary* otherProperties = [NSClassFromString(property.type) propertyDefinitions];
         for (NSString* otherName in otherProperties)
         {
         DBPropertyDefinition* otherProperty = otherProperties[otherName];
         // reciprocal relationship
         if([NSClassFromString(otherProperty.type) isKindOfClass: self])
         {
         
         }
         
         }
         }
         */
    }
    return columns;
}

+(void)createTable
{
    [[self queue]inDatabase:^(FMDatabase *db) {
        [self createTableInDatabase:db];
    }];
}

+(void)createTableInDatabase:(FMDatabase*)db
{
    NSDictionary* columns = [self columnDefinitionsFromProperties];
    NSMutableArray* defs = [NSMutableArray arrayWithCapacity:columns.count+1];
    for (NSString* key in columns) {
        id value = columns[key];
        [defs addObject:[NSString stringWithFormat: @"[%@] %@",key,value]];
    }
    NSArray* pkNames = [self primaryKeyPropertyNames];
    NSMutableArray* primaryKeys = [NSMutableArray arrayWithCapacity:[pkNames count]];
    for (NSString* k in pkNames) {
        [primaryKeys addObject:[NSString stringWithFormat:@"[%@]",k]];
    }
    [defs addObject:[NSString stringWithFormat:@"PRIMARY KEY(%@)",[primaryKeys componentsJoinedByString:@", "]]];
    NSString* sql = [NSString stringWithFormat:@"CREATE TABLE IF NOT EXISTS [%@] (%@)",
                     [self tablename],[defs componentsJoinedByString:@", " ]];
    [db executeUpdate:sql];
}

+(void)dropTable
{
    [[self queue]inDatabase:^(FMDatabase *db) {
        [self dropTableInDatabase:db];
    }];
}

+(void)dropTableInDatabase:(FMDatabase*)db
{
    [db executeQuery:[NSString stringWithFormat:@"DROP TABLE IF EXISTS [%@]",[self tablename]]];
    [schema removeObjectForKey:[self tablename]];
}

+(NSString*)tablename
{
    NSString* classname = NSStringFromClass(self);
    NSArray* pair = [classname componentsSeparatedByString:@"."];
    if([pair count] > 1)
    {
        return [[pair lastObject]lowercaseString];
    }
    return [[classname substringFromIndex:2]lowercaseString];
}

-(NSString*)tablename
{
    return [[self class]tablename];
}

+(NSArray*)columns
{
    NSMutableDictionary* schema = self.schema;
    NSArray* __block cols = schema[@"Columns"];
    
    if(![cols count])
    {
        [[self queue]inDatabase:^(FMDatabase *db) {
            cols = [self columnsInDatabase:db];
        }];
    }
    return cols;
}

+(NSArray*)columnsInDatabase:(FMDatabase*)db
{
    NSMutableDictionary* schema = self.schema;
    NSArray* cols = schema[@"Columns"];
    if(![cols count])
    {
        cols = [db schemaForTable:[self tablename]];
        schema[@"Columns"] = cols;
    }
    return cols;
}

-(NSArray*)columns
{
    return [[self class]columns];
}

+(NSArray*)columnNamesInDatabase:(FMDatabase*)db
{
    return [[self columnsInDatabase:db]valueForKeyPath:@"name"];
}

+(NSArray*)columnNames
{
    return [[self columns]valueForKeyPath:@"name"];
}

-(NSArray*)columnNames
{
    return [[self class]columnNames];
}

+(NSArray*)primaryKeyColumns
{
    NSMutableDictionary* schema = self.schema;
    NSArray* primaryKeyColumns = schema[@"PrimaryKeyColumns"];
    if(!primaryKeyColumns)
    {
        NSArray* columns = [self columns];
        NSMutableArray* pks = [NSMutableArray arrayWithCapacity:[columns count]];
        for (NSDictionary* obj in [self columns]) {
            if([obj[@"pk"]boolValue]) { [pks addObject:obj]; }
        }
        primaryKeyColumns = pks;
        schema[@"PrimaryKeyColumns"] = primaryKeyColumns;
    }
    return primaryKeyColumns;

}

+(NSArray*)primaryKeyColumnsInDatabase:(FMDatabase*)db
{
    NSMutableDictionary* schema = self.schema;
    NSArray* primaryKeyColumns = schema[@"PrimaryKeyColumns"];
    if(!primaryKeyColumns)
    {
        NSArray* columns = [self columnsInDatabase:db];
        NSMutableArray* pks = [NSMutableArray arrayWithCapacity:[columns count]];
        for (NSDictionary* obj in [self columnsInDatabase:db]) {
            if([obj[@"pk"]boolValue]) { [pks addObject:obj]; }
        }
        primaryKeyColumns = pks;
        schema[@"PrimaryKeyColumns"] = primaryKeyColumns;
    }
    return primaryKeyColumns;
}

+(NSArray*)primaryKeyColumnNamesInDatabase:(FMDatabase*)db
{
    return [[self primaryKeyColumnsInDatabase:db]valueForKeyPath:@"name"];
}

+(NSString*)cacheDirectory
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    return [paths lastObject];
}

+(NSString*)documentsDirectory
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    return documentsDirectory;
}

-(NSArray*)primaryKeyColumnNamesInDatabase:(FMDatabase*)db
{
    return [[self class]primaryKeyColumnsInDatabase:db];
}

-(NSArray*)primaryKeyColumns
{
    return [[self class]primaryKeyColumns];
}

+(NSArray*)primaryKeyColumnNames
{
    return [[self primaryKeyColumns]valueForKeyPath:@"name"];
}

-(NSArray*)primaryKeyColumnNames
{
    return [[self class]primaryKeyColumnNames];
}

+(NSArray*)serverColumnNames
{
    return [self columnNames];
}

-(NSArray*)serverColumnNames
{
    return [[self class]serverColumnNames];
}

+(NSArray*)placeholders:(NSInteger)count
{
    NSMutableArray* array = [NSMutableArray arrayWithCapacity:count];
    if(count <= 0) return array;
    while(count--)
    {
        [array addObject: @"?"];
    }
    return array;
}

-(NSArray*)placeholders:(NSInteger)count
{
    return [[self class]placeholders:count];
}

+(NSString*)placeholderString:(NSInteger)count
{
    return [[self placeholders:count]componentsJoinedByString:@", "];
}

-(NSString*)placeholderString:(NSInteger)count
{
    return [[self class]placeholderString:count];
}

+(NSString*)selectKeyClause
{
    NSArray* keys = self.primaryKeyColumnNames;
    return [NSString stringWithFormat:@"SELECT %@ FROM [%@] ",[keys componentsJoinedByString:@", "],[self tablename]];
}

+(NSString*)selectClause
{
    return [NSString stringWithFormat:@"SELECT * FROM [%@] ",[self tablename]];
}

+(NSString*)selectCountClause
{
    return [NSString stringWithFormat:@"SELECT count(*) FROM [%@] ",[self tablename]];
}

+(NSString*)orderByClauseFromOrderings:(NSArray*)cols
{
    NSMutableArray* terms = [NSMutableArray arrayWithCapacity: [cols count]];
    for (NSArray* pair in cols) {
        [terms addObject:[pair componentsJoinedByString:@" "]];
    }
    
    if(terms.count)
    {
        return [NSString stringWithFormat: @" ORDER BY %@ ",[terms componentsJoinedByString:@", "]];
    }
    return @"";
}

+(NSString*)orderByClause
{
    return [self orderByClauseFromOrderings:[self orderByColumns]];
}

+(NSString*)reverseOrderByClause
{
    return [self orderByClauseFromOrderings:[self reverseOrderByColumns]];
}

+(NSArray*)orderByColumns
{
    return @[@[@"id", @"DESC"]];
}

-(NSArray*)orderByColumns
{
    return [[self class]orderByColumns];
}

+(NSArray*)reverseOrderByColumns
{
    return [self reverseOrderBy:[self reverseOrderByColumns]];
}

-(NSArray*)reverseOrderByColumns
{
    return [[self class]reverseOrderByColumns];
}

+(NSArray*)reverseOrderBy:(NSArray*)orderBy
{
    static NSDictionary* inverse = nil;
  
    if(!inverse) { inverse = @{@"DESC": @"ASC", @"ASC": @"DESC"}; }
    return [orderBy collect:^id(NSArray* pair) {
        NSString* direction = [pair[1] uppercaseString];
        return @[pair[0], inverse[direction]];
    }];
}

+(BOOL)key:(id)key toWhereClause:(NSString**)wc values:(NSArray**)vs inDatabase:(FMDatabase*)db
{
    NSMutableArray* whereClause = [NSMutableArray array];
    NSMutableArray* values = [NSMutableArray array];
    
    if([key isKindOfClass:[NSDictionary class]])
    {
        for(NSString* k in key)
        {
            id value = [key objectForKey: k];
            if([value isKindOfClass:[NSArray class]])
            {
                NSArray* placeholders = [value collect:^id(id v) {
                    [values addObject: v];
                    return @"?";
                }];
                
                [whereClause addObject: [NSString stringWithFormat:@"[%@].[%@] IN (%@)",[self tablename],k,[placeholders componentsJoinedByString:@", "]]];
            }
            else
            {
                [whereClause addObject: [NSString stringWithFormat:@"[%@].[%@] = ?",[self tablename],k]];
                [values addObject: [key objectForKey: k]];
            }
        }
        *vs = values;
        *wc = [@" WHERE " stringByAppendingString:[whereClause componentsJoinedByString:@" AND "]];
    }
    else if (key && [[self primaryKeyColumnsInDatabase:db]count] == 1)
    {
        [whereClause addObject: [NSString stringWithFormat:@"[%@].[%@] = ?", [self tablename],[[self primaryKeyColumnNames]lastObject]]];
        [values addObject: key];
        *vs = values;
        *wc = [@" WHERE " stringByAppendingString:[whereClause componentsJoinedByString:@" AND "]];
    }
    else // going for all
    {
        *wc = @"";
        *vs = values;
    }
    return YES;
}

+(BOOL)key:(id)key toNextWhereClause:(NSString**)wc values:(NSArray**)vs inDatabase:(FMDatabase*)db
{
    [self columnsInDatabase:db];
    NSMutableArray* whereClause = [NSMutableArray array];
    NSMutableArray* values = [NSMutableArray array];
    NSArray* orders = self.orderByColumns;
    
    if([key isKindOfClass:[NSDictionary class]])
    {
        for(NSString* k in key)
        {
            NSArray* pair = [orders detect:^BOOL(NSArray* p) {
                return [p[0] rangeOfString:k].length > 0;
            }];
            
            if(pair)
            {
                if([pair[1] isEqualToString:@"ASC"])
                {
                    [whereClause addObject: [NSString stringWithFormat:@"%@ > ?",pair[0]]];
                }
                else
                {
                    [whereClause addObject: [NSString stringWithFormat:@"%@ < ?",pair[0]]];
                }
                [values addObject: [key objectForKey: k]];
            }
            else
            {
                [whereClause addObject: [NSString stringWithFormat:@"[%@].[%@] = ?",[self tablename],k]];
                [values addObject: [key objectForKey: k]];
            }
        }
        *vs = values;
        *wc = [@" WHERE " stringByAppendingString:[whereClause componentsJoinedByString:@" AND "]];
        return YES;
    }
    else if (key && [[self primaryKeyColumns]count] == 1 && orders.count == 1)
    {
        NSArray* pair = orders.lastObject;
        if([pair[1] isEqualToString:@"ASC"])
        {
            [whereClause addObject: [NSString stringWithFormat:@"[%@] > ?", pair[0]]];
        }
        else
        {
            [whereClause addObject: [NSString stringWithFormat:@"[%@] < ?", pair[0]]];
        }
        [values addObject: key];
        *vs = values;
        *wc = [@" WHERE " stringByAppendingString:[whereClause componentsJoinedByString:@" AND "]];
        return YES;
    }
    else // going for all
    {
        *wc = @"";
        *vs = values;
    }
    return YES;
}

+(BOOL)key:(id)key toPreviousWhereClause:(NSString**)wc values:(NSArray**)vs inDatabase:(FMDatabase*)db
{
    [self columnsInDatabase:db];
    NSMutableArray* whereClause = [NSMutableArray array];
    NSMutableArray* values = [NSMutableArray array];
    NSArray* orders = self.orderByColumns;
    
    if([key isKindOfClass:[NSDictionary class]])
    {
        for(NSString* k in key)
        {
            NSArray* pair = [orders detect:^BOOL(NSArray* p) {
                return [p[0] rangeOfString:k].length > 0;
            }];
            
            if(pair)
            {
                if([pair[1] isEqualToString:@"ASC"])
                {
                    [whereClause addObject: [NSString stringWithFormat:@"[%@] < ?",pair[0]]];
                }
                else
                {
                    [whereClause addObject: [NSString stringWithFormat:@"[%@] > ?",pair[0]]];
                }
                [values addObject: [key objectForKey: k]];
            }
            else
            {
                [whereClause addObject: [NSString stringWithFormat:@"[%@].[%@] = ?",[self tablename],k]];
                [values addObject: [key objectForKey: k]];
            }
        }
        *vs = values;
        *wc = [@" WHERE " stringByAppendingString:[whereClause componentsJoinedByString:@" AND "]];
        return YES;
    }
    else if (key && [[self primaryKeyColumns]count] == 1 && orders.count == 1)
    {
        NSArray* pair = orders.lastObject;
        if([pair[1] isEqualToString:@"ASC"])
        {
            [whereClause addObject: [NSString stringWithFormat:@"[%@] < ?", pair[0]]];
        }
        else
        {
            [whereClause addObject: [NSString stringWithFormat:@"[%@] > ?", pair[0]]];
        }
        [values addObject: key];
        *vs = values;
        *wc = [@" WHERE " stringByAppendingString:[whereClause componentsJoinedByString:@" AND "]];
        return YES;
    }
    else // going for all
    {
        *wc = @"";
        *vs = values;
    }
    return YES;
}

+(NSUInteger)countInDatabase:(FMDatabase*)db
{
    return [self countWhere:nil inDatabase:db];
}

+(NSUInteger)count
{
    return [self countWhere:nil];
}

+(NSUInteger)countWhere:(NSDictionary*)where inDatabase:(FMDatabase*)db
{
    NSString* whereClause = nil;
    NSArray* values = nil;
    
    if(![self key:where toWhereClause:&whereClause values:&values inDatabase:db]) { return 0; }
    
    return [self countWhereSql:whereClause parameters:values inDatabase:db];

}

+(NSUInteger)countWhere:(NSDictionary*)where
{
    NSUInteger __block count = 0;
    [[self queue]inDatabase:^(FMDatabase *db) {
        count = [self countWhere:where inDatabase:db];
    }];
    return count;
}


+(NSUInteger)countWhereSql:(NSString*)where parameters:(NSArray*)parms inDatabase:(FMDatabase*)db
{
    NSString* sql = [self selectCountClause];
    if([where length])
    {
        sql = [sql stringByAppendingString: where];
    }
    FMResultSet* set = [db executeQuery:sql withArgumentsInArray:parms];
    if([set next])
    {
        NSUInteger count =  (NSUInteger)[set unsignedLongLongIntForColumnIndex:0];
        [set close];
        return count;
    }
    return 0;
}

+(NSUInteger)countWhereSql:(NSString*)where parameters:(NSArray *)params
{
    NSUInteger __block count = 0;
    [[self queue]inDatabase:^(FMDatabase *db) {
        count = [self countWhereSql:where parameters:params inDatabase:db];
    }];
    return count;
}

+(instancetype)firstInDatabase:(FMDatabase *)db
{
    return [self find:nil orderBy:[self orderByColumns] limit: 1 inDatabase:db];
}

+(instancetype)first
{
    return [self find:nil orderBy:[self orderByColumns] limit: 1];
}

+(instancetype)lastInDatabase:(FMDatabase *)db
{
    return [self find:nil orderBy:[self reverseOrderByColumns] limit: 1 inDatabase:db];
}

+(instancetype)last
{
    return [self find:nil orderBy:[self reverseOrderByColumns] limit: 1];
}

+(NSArray*)all
{
    NSArray* __block result = nil;
    [[self queue]inDatabase:^(FMDatabase *db) {
        result = [self allInDatabase:db];
    }];
    return result;
}

+(NSArray*)allInDatabase:(FMDatabase*)db
{
    id object = [self findAll:nil inDatabase:db];
    if(object && ![object isKindOfClass: [NSArray class]])
    {
        return @[object];
    }
    return object;
}

+(id)find:(id)key orderBy:(NSArray*)orderings inDatabase:(FMDatabase*)db
{
    return [self find:key orderBy:orderings limit: 0 inDatabase:db];
}

+(id)find:(id)key orderBy:(NSArray*)orderings
{
    return [self find: key orderBy:orderings limit:0];
}

+(id)find:(id)key orderBy:(NSArray*)orderings limit:(NSInteger)limit inDatabase:(FMDatabase*)db
{
    return [self find:key orderBy:orderings limit:limit offset:0 inDatabase:db];
}

+(id)find:(id)key orderBy:(NSArray*)orderings limit:(NSInteger)limit
{
    return [self find:key orderBy:orderings limit:limit offset:0];
}

+(id)find:(id)key orderBy:(NSArray*)orderings limit:(NSInteger)limit offset:(NSInteger)offset inDatabase:(FMDatabase*)db
{
    NSString* whereClause = nil;
    NSArray* values = nil;
    
    if(![self key:key toWhereClause:&whereClause values:&values inDatabase:db]) { return nil; }
    
    NSString* sql = [[[self selectClause] stringByAppendingString: whereClause] stringByAppendingString: [self orderByClauseFromOrderings:orderings]];

    //LIMIT <count> OFFSET <skip>
    if(limit > 0)
    {
        sql = [sql stringByAppendingFormat:@" LIMIT %ld", (long)limit];
    }
    
    if(offset > 0)
    {
        sql = [sql stringByAppendingFormat: @" OFFSET %ld", (long)offset];
    }
    
    NSArray* objects = [self findBySql:sql parameters:values inDatabase:db];
    return limit == 1 && objects.count == 1 ? [objects lastObject] : (objects.count == 0 ? nil : objects);
}

+(id)find:(id)key orderBy:(NSArray*)orderings limit:(NSInteger)limit offset:(NSInteger)offset
{
    id __block found = nil;
    [[self queue]inDatabase:^(FMDatabase *db) {
        found = [self find: key orderBy:orderings limit:limit offset:offset inDatabase:db];
    }];
    return found;
}

+(id)find:(id)key limit:(NSInteger)limit
{
    return [self find:key orderBy:[self orderByColumns] limit:limit offset:0];
}

+(id)find:(id)key limit:(NSInteger)limit inDatabase:(FMDatabase*)db
{
    return [self find:key orderBy:[self orderByColumns] limit:limit offset:0 inDatabase:db];
}

+(NSArray*)findAll:(id)key limit:(NSInteger) limit
{
    return [self find:key orderBy:[self orderByColumns] limit:limit offset:0];
}

+(NSArray*)findAll:(id)key limit:(NSInteger) limit inDatabase:(FMDatabase*)db
{
    return [self find:key orderBy:[self orderByColumns] limit:limit offset: 0 inDatabase:db];
}

+(NSArray*)findAll:(id)key
{
    return [self find:key orderBy:[self orderByColumns] limit:0 offset: 0];
}

+(NSArray*)findAll:(id)key inDatabase:(FMDatabase *)db
{
    return [self find:key orderBy:[self orderByColumns] limit:0 offset: 0 inDatabase:db];
}

+(id)find:(id)key
{
    return [self find:key orderBy:[self orderByColumns] limit:1 offset: 0];
}

+(id)find:(id)key inDatabase:(FMDatabase*)db
{
    return [self find:key orderBy:[self orderByColumns] limit:1 offset: 0 inDatabase:db];
}

+(NSArray*)findBySql:(NSString*)sql parameters:(NSArray*)params
{
    NSArray* __block objects = nil;
    [[self queue] inDatabase:^(FMDatabase *db) {
        objects = [self findBySql:sql parameters:params inDatabase:db];
    }];
    return objects;
}

+(NSArray*)findBySql:(NSString*)sql parameters:(NSArray*)params inDatabase:(FMDatabase*)db
{
    FMResultSet* set = [db executeQuery:sql withArgumentsInArray:params];
    NSMutableArray* objects = [NSMutableArray array];
    [self columnsInDatabase:db];

    while([set next])
    {
        [objects addObject:[self cachedObjectForDictionary: [set resultDictionary]]];
    }
    return objects;
}

+(NSArray*)findBySqlWhere:(NSString*)where parameters:(NSArray*)params inDatabase:(FMDatabase*)db
{
    NSString* sql = [self selectClause];
    if([where length])
    {
        sql = [NSString stringWithFormat: @"%@ WHERE %@",sql,where];
    }
    FMResultSet* set = [db executeQuery:sql withArgumentsInArray:params];
    NSMutableArray* objects = [NSMutableArray array];
    [self columnsInDatabase:db];
    
    while([set next])
    {
        [objects addObject:[self cachedObjectForDictionary: [set resultDictionary]]];
    }
    return objects;

}

+(NSArray*)findBySqlWhere:(NSString*)sql parameters:(NSArray*)params
{
    NSArray* __block objects = nil;
    [[self queue] inDatabase:^(FMDatabase *db) {
        objects = [self findBySqlWhere:sql parameters:params inDatabase:db];
    }];
    return objects;
}


+(void)remove:(id)key
{
    [[self queue]inDatabase:^(FMDatabase *db) {
        [self remove:key inDatabase: db];
    }];
}

+(void)remove:(id)key inDatabase:(FMDatabase*)db
{
    NSString* whereClause = nil;
    NSArray* values = nil;
    
    NSMapTable* cache = [self cache];
    if (cache && [cache respondsToSelector:@selector(removeObjectForKey:)])
        [cache removeObjectForKey:key];
    
    if(![self key:key toWhereClause:&whereClause values:&values inDatabase:db])
    {
        NSLog(@"%@ remove where: %@",self,key);
        return;
    }
    
    NSString* sql = [NSString stringWithFormat:@"DELETE FROM [%@] %@",[self tablename],whereClause];
    [db executeUpdate:sql withArgumentsInArray:values];
}

-(NSArray*)nextObjects:(NSInteger)limit
{
    NSArray* __block next = nil;
    [[self queue]inDatabase:^(FMDatabase *db) {
        next = [self nextObjects:limit inDatabase:db];
    }];
    return next;
}

-(NSArray*)nextObjects:(NSInteger)limit inDatabase:(FMDatabase*)db
{
    NSDictionary* key = self.primaryKeyValues;
    
    NSString* whereClause = nil;
    NSArray* values = nil;
    
    if(![self.class key:key toNextWhereClause:&whereClause values:&values inDatabase:db]) { return nil; }
    
    NSString* sql = [[[self.class selectClause] stringByAppendingString: whereClause] stringByAppendingString: [self.class orderByClause]];
    
    if(limit > 0)
    {
        sql = [sql stringByAppendingFormat:@" LIMIT %ld", (long)limit];
    }
    
    NSArray* objects = [self.class findBySql:sql parameters:values];
    
    return objects;
}

-(NSArray*)previousObjects:(NSInteger)limit
{
    NSArray* __block next = nil;
    [[self queue]inDatabase:^(FMDatabase *db) {
        next = [self previousObjects:limit inDatabase:db];
    }];
    return next;
}


-(NSArray*)previousObjects:(NSInteger)limit inDatabase:(FMDatabase*)db
{
    NSDictionary* key = self.primaryKeyValues;
    
    NSString* whereClause = nil;
    NSArray* values = nil;
    
    if(![self.class key:key toPreviousWhereClause:&whereClause values:&values inDatabase:db]) { return nil; }
    
    NSString* sql = [[[self.class selectClause] stringByAppendingString: whereClause] stringByAppendingString: [self.class reverseOrderByClause]];
    
    if(limit > 0)
    {
        sql = [sql stringByAppendingFormat:@" LIMIT %ld", (long)limit];
    }
    
    NSArray* objects = [self.class findBySql:sql parameters:values];
    
    return objects;
}

-(void)periodicActivity:(NSNotification*)note
{
    
}

-(NSArray*)names
{
    return [[self class].columnNames sortedArrayUsingSelector:@selector(compare:)];
}

-(NSArray*)values
{
    NSArray* names = self.names;
    NSMutableArray* v = [NSMutableArray arrayWithCapacity:names.count];
    for (NSString* n in names)
    {
        id obj = [self valueForKey:n];
        [v addObject: obj];
    }
    return v;
}

-(NSArray*)placeholders
{
    NSInteger count = self.names.count;
    NSMutableArray* v = [NSMutableArray arrayWithCapacity:count];
    for (int i = 0; i < count; ++i)
    {
        [v addObject: @"?"];
    }
    return v;
}

-(NSString*)uniqueIdentifer
{
    NSDictionary* pks = self.primaryKeyValues;
    if (!pks) return @"";
    return [pks.allValues componentsJoinedByString:@"-"];
}

-(NSDictionary*)primaryKeyValues
{
    return [self dictionaryWithValuesForKeys:[[self class]primaryKeyColumnNames]];
}

-(NSDictionary*)databaseColumnValues
{
    return [self dictionaryWithValuesForKeys:[[self class]columnNames]];
}

-(NSDictionary*)serverColumnValues
{
    return [self dictionaryWithValuesForKeys:[[self class]serverColumnNames]];
}

-(NSArray*)arrayWithValuesForKeys:(NSArray*)keys
{
    return [keys collect:^(id k){
        id value = [self valueForKey:k];
        
        return value==nil ? [NSNull null] : value;
    }];
}

-(BOOL)save
{
    BOOL __block result = YES;
    [[self queue]inDatabase:^(FMDatabase *db) {
        result = [self saveInDatabase: db];
    }];
    return result;
}

-(BOOL)saveInDatabase:(FMDatabase*)db
{
    NSArray* names = [[self class]columnNamesInDatabase:db];
    NSArray* primaryKeyCols = [[self class]primaryKeyColumnsInDatabase:db];
    
    BOOL shouldCopyBackPrimaryKey = NO;
    
    if([primaryKeyCols count] == 1)
    {
        NSDictionary* def = primaryKeyCols[0];
        if([def[@"type"] isEqualToString:@"INTEGER"])
        {
            id pk = [self primaryKeyValues][def[@"name"]];
            if([pk isKindOfClass:[NSNull class]] || [pk longLongValue] == 0)
            {
                shouldCopyBackPrimaryKey = YES;
                names = [names copyWithout:def[@"name"]];
            }
        }
    }
    
    NSArray* escaped = [names collect:^id(id s) {
        return [NSString stringWithFormat:@"[%@]",s];
    }];
    NSArray* values = [self arrayWithValuesForKeys:names];
    
    NSString* sql = [NSString stringWithFormat:@"INSERT OR REPLACE INTO [%@] (%@) VALUES (%@)",[[self class]tablename],[escaped componentsJoinedByString: @", "],[[self class]placeholderString:names.count]];
    
    [db executeUpdate:sql withArgumentsInArray:values];
    if(shouldCopyBackPrimaryKey)
    {
        NSDictionary* def = primaryKeyCols[0];
        [self setValue:@([db lastInsertRowId]) forKey:def[@"name"]];
    }
    
    [self refreshInDatabase:db];
    return YES;
}

-(void)remove
{
    [[self class]remove:[self primaryKeyValues]];
}

-(void)removeInDatabase:(FMDatabase*)db
{
    [[self class]remove:[self primaryKeyValues] inDatabase:db];
}

-(void)refresh
{
    [[self queue]inDatabase:^(FMDatabase *db) {
        [self refreshInDatabase: db];
    }];
}

-(void)refreshInDatabase:(FMDatabase*)db
{
    NSDictionary* key = self.primaryKeyValues;
    
    NSString* whereClause = nil;
    NSArray* values = nil;
    
    if(![self.class key:key toWhereClause:&whereClause values:&values inDatabase:db])
    {
        [NSException raise:@"Attempt to refresh non-persistent object" format:@"%@",self];
        return;
    }
    
    NSString* sql = [[[self.class selectClause] stringByAppendingString: whereClause] stringByAppendingString: [self.class orderByClause]];
    
    
    FMResultSet* set = [db executeQuery:sql withArgumentsInArray:values];
    while([set next])
    {
        [set kvcMagic:self];
    }
}

-(NSURL*)cacheLocationForMediaURL:(NSURL*)url;
{
    NSArray* path = url.pathComponents;
    NSString* cachePath = [[[self class] cacheDirectory]stringByAppendingPathComponent:path[path.count-2]];
    cachePath = [cachePath stringByAppendingPathComponent:path.lastObject];
    return [NSURL fileURLWithPath:cachePath];
}

-(BOOL)mediaURLIsCached:(NSURL*)url
{
    if(![url.scheme isEqualToString: @"file"])
    {
        url = [self cacheLocationForMediaURL:url];
    }
    return [[NSFileManager defaultManager]fileExistsAtPath:url.path];
}


// Equality tests - be very careful here

- (BOOL)isEqual:(id)other
{
    if (other == self)
        return YES;
    if (!other || ![other isMemberOfClass:[self class]])
        return NO;
    DBModel* tother = other;
    return [self.primaryKeyValues isEqualToDictionary: tother.primaryKeyValues];
}

- (NSUInteger)hash
{
    // if our keys and class is the same we should have the same hash
    return [self.primaryKeyValues hash] + [[[self class] description]hash];
}

-(NSString*)description
{
    return [NSString stringWithFormat:@"%@ : %@",[self class],self.primaryKeyValues];
}

-(void)dealloc
{
    // crash proofing
    [[NSNotificationCenter defaultCenter]removeObserver:self];
}

-(void)finalize
{
    // crash proofing
    [[NSNotificationCenter defaultCenter]removeObserver:self];
}

@end
