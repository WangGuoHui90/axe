//
//  AXEData+JavaScriptSupport.m
//  Axe
//
//  Created by 罗贤明 on 2018/3/11.
//  Copyright © 2018年 罗贤明. All rights reserved.
//

#import "AXEData+JavaScriptSupport.h"
#import "AXEJavaScriptModelData.h"
#import "AXEDefines.h"
#import "AXEBasicTypeData.h"
#import <objc/runtime.h>

@interface AXEBaseData (JavaScriptSupport)
//储存原始数据， 以避免 js模块互相传递数据时的额外消耗。
@property (nonatomic,strong) NSDictionary *javascriptData;
@end

@implementation AXEBaseData(JavaScriptSupport)
- (void)setJavascriptData:(NSDictionary *)raw {
    objc_setAssociatedObject(self, @selector(javascriptData), raw, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSDictionary *)javascriptData {
    return objc_getAssociatedObject(self, @selector(javascriptData));
}
@end


// 获取私有接口。
@interface AXEData(JavaScriptSupportPrivate)
@property (nonatomic,strong) NSMutableDictionary<NSString *,AXEBaseData *> *storedDatas;
@end

@implementation AXEData(JavaScriptSupport)

- (void)setJavascriptData:(NSDictionary *)data forKey:(NSString *)key{
    if ([data isKindOfClass:[NSDictionary class]] && [key isKindOfClass:[NSString class]]) {
        NSString *value = [data objectForKey:@"value"];
        NSString *type = [data objectForKey:@"type"];
        AXEBaseData *saved;
        if ([type isEqualToString:@"Number"]) {
            saved = [AXEBasicTypeData basicDataWithNumber:[NSDecimalNumber decimalNumberWithString:value]];
        }else if ([type isEqualToString:@"String"]) {
            saved = [AXEBasicTypeData basicDataWithString:value];
        }else if ([type isEqualToString:@"Array"]) {
            NSData *valueData = [value dataUsingEncoding:NSUTF8StringEncoding];
            NSError *error;
            NSArray *list = [NSJSONSerialization JSONObjectWithData:valueData options:0 error:&error];
            if (error || ![list isKindOfClass:[NSArray class]]) {
                AXELogWarn(@" 设置AXEData， 设定类型为Array,但是当前数据格式校验错误 。 数据为 %@",data);
                return;
            }
            saved = [AXEBasicTypeData basicDataWithArray:list];
        }else if ([type isEqualToString:@"Object"]) {
            NSData *valueData = [value dataUsingEncoding:NSUTF8StringEncoding];
            NSError *error;
            NSDictionary *dic = [NSJSONSerialization JSONObjectWithData:valueData options:0 error:&error];
            if (error || ![dic isKindOfClass:[NSDictionary class]]) {
                AXELogWarn(@" 设置AXEData， 设定类型为Object,但是当前数据格式校验错误 。 数据为 %@",data);
                return;
            }
            saved = [AXEBasicTypeData basicDataWithDictionary:dic];
        }else if([type isEqualToString:@"Image"]) {
            // javascript中实际存储的格式为 ： data:image/jpeg;base64,xxxx
            NSRange range = [value rangeOfString:@";base64,"];
            if (range.location == NSNotFound) {
                AXELogWarn(@"设置的图片格式不正确， 需要为 data:image/jpeg;base64, 开头的base64字符串！！");
                return;
            }
            value = [value substringFromIndex:range.location + range.length];
            NSData *reserved = [[NSData alloc] initWithBase64EncodedString:value options:NSDataBase64DecodingIgnoreUnknownCharacters];
            if ([reserved isKindOfClass:[NSData class]]) {
                saved = [AXEBasicTypeData basicDataWithImage:[UIImage imageWithData:reserved]];
            }
        }else if ([type isEqualToString:@"Data"]) {
            NSData *reserved = [[NSData alloc] initWithBase64EncodedString:value options:NSDataBase64DecodingIgnoreUnknownCharacters];
            if ([reserved isKindOfClass:[NSData class]]) {
                saved = [AXEBasicTypeData basicDataWithData:reserved];
            }
        }else if ([type isEqualToString:@"Date"]) {
            long long time = [value longLongValue];
            NSTimeInterval timeInterval = time / 1000.;
            NSDate *date = [NSDate dateWithTimeIntervalSince1970:timeInterval];
            saved = [AXEBasicTypeData basicDataWithDate:date];
        }else if ([type isEqualToString:@"Boolean"]) {
            BOOL boo = [value boolValue];
            saved = [AXEBasicTypeData basicDataWithBoolean:boo];
        }
        if (saved) {
            [saved setJavascriptData:data];
            [self.storedDatas setObject:saved forKey:key];
            return;
        }
        if ([type isEqualToString:@"Model"]) {
            // model 类型。 还要再特殊处理一下
            NSData *valueData = [value dataUsingEncoding:NSUTF8StringEncoding];
            NSError *error;
            NSDictionary *dic = [NSJSONSerialization JSONObjectWithData:valueData options:0 error:&error];
            if (error || ![dic isKindOfClass:[NSDictionary class]]) {
                AXELogWarn(@" 设置AXEData， 设定类型为Model,但是当前数据格式校验错误 。 数据为 %@",data);
                return;
            }
            AXEModelTypeData *currentModelData = (AXEModelTypeData *)[self dataForKey:key];
            if ([currentModelData isMemberOfClass:[AXEModelTypeData class]]) {
                // 根据传入的json 重新设置model类型的值。
                id<AXEDataModelProtocol> currentModel = currentModelData.value;
                [currentModel axe_modelSetWithJSON:dic];
            }else {
                // 否则为 当前无model， 或者是 js的model， 则创建一个新的jsmodel.
                AXEJavaScriptModelData *modelData = [AXEJavaScriptModelData javascriptModelWithValue:dic];
                [self.storedDatas setObject:modelData forKey:key];
            }
        }
    } else {
        AXELogWarn(@"setJavascriptData 传入错误的参数 ： %@ ",key);
    }
}


- (NSDictionary *)javascriptDataForKey:(NSString *)key {
    if (![key isKindOfClass:[NSString class]]) {
        AXELogWarn(@"key 需要为字符串类型！");
        return nil;
    }
    AXEBaseData *data = [self.storedDatas objectForKey:key];
    if (!data) {
        return nil;
    }
    NSMutableDictionary *javascriptData = [[NSMutableDictionary alloc] initWithCapacity:2];
    // 检测数据类型，并做相应的转换。
    if ([data isKindOfClass:[AXEBasicTypeData class]]) {
        // 基础数据类型。
        if (data.javascriptData) {
            // 直接返回, 避免js之间的额外转换
            return data.javascriptData;
        }
        
        AXEDataBasicType type = [(AXEBasicTypeData *)data basicType];
        if (type == AXEDataBasicTypeNumber) {
            javascriptData[@"type"] = @"Number";
            javascriptData[@"value"] = [data.value stringValue];
        }else if (type == AXEDataBasicTypeString) {
            javascriptData[@"type"] = @"String";
            javascriptData[@"value"] = data.value;
        }else if (type == AXEDataBasicTypeArray) {
            javascriptData[@"type"] = @"Array";
            NSError *error;
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:data.value options:0 error:&error];
            if (error) {
                AXELogWarn(@" javascript 所需要的 Array类型，必须能转换为json， 当前json转换出错 %@",error);
                return nil;
            }
            javascriptData[@"value"] = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        }else if (type == AXEDataBasicTypeDictionary) {
            javascriptData[@"type"] = @"Object";
            NSError *error;
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:data.value options:0 error:&error];
            if (error) {
                AXELogWarn(@" javascript 所需要的 Object类型，必须能转换为json， 当前json转换出错 %@",error);
                return nil;
            }
            javascriptData[@"value"] = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        }else if (type == AXEDataBasicTypeUIImage) {
            javascriptData[@"type"] = @"Image";
            UIImage *image = data.value;
            // 图片固定格式 jpeg 。
            NSData *imageData = UIImageJPEGRepresentation(image, 1.0);
            NSString *base64Data = [imageData base64EncodedStringWithOptions:NSDataBase64Encoding64CharacterLineLength];
            javascriptData[@"value"] = [@"data:image/jpeg;base64," stringByAppendingString:base64Data];
        }else if (type == AXEDataBasicTypeData) {
            javascriptData[@"type"] = @"Data";
            javascriptData[@"value"] = [data.value base64EncodedStringWithOptions:NSDataBase64Encoding64CharacterLineLength];
        }else if (type == AXEDataBasicTypeDate) {
            javascriptData[@"type"] = @"Date";
            NSDate *date = data.value;
            long long value = [date timeIntervalSince1970] * 1000;
            javascriptData[@"value"] = [@(value) stringValue];
        }else if (type == AXEDataBasicTypeBoolean) {
            javascriptData[@"type"] = @"Boolean";
            javascriptData[@"value"] = [data.value boolValue] ? @"true":@"false";
        }
    }else if ([data isKindOfClass:[AXEModelTypeData class]]) {
        // model类型。
        javascriptData[@"type"] = @"Model";
        id<AXEDataModelProtocol> model = data.value;
        NSDictionary *modeDict = [model axe_modelToJSONObject];
        NSError *error;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:modeDict options:0 error:&error];
        if (error) {
            AXELogWarn(@" javascript 所需要的 Model类型，必须能转换为json， 当前json转换出错 %@",error);
            return nil;
        }
        javascriptData[@"value"] = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    }
    return javascriptData;
}


+ (NSDictionary *)javascriptDataFromAXEData:(AXEData *)data {
    if ([data isKindOfClass:[AXEData class]]) {
        NSMutableDictionary *javascriptData = [[NSMutableDictionary alloc] init];
        [data.storedDatas enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, AXEBaseData * _Nonnull obj, BOOL * _Nonnull stop) {
            NSDictionary *singleData = [data javascriptDataForKey:key];
            if (singleData) {
                [javascriptData setObject:singleData forKey:key];
            }
        }];
        return javascriptData;
    }else {
        return  nil;
    }
}

+ (AXEData *)axeDataFromJavascriptData:(NSDictionary *)javascriptData {
    if ([javascriptData isKindOfClass:[NSDictionary class]]) {
        AXEData *data = [AXEData dataForTransmission];
        [javascriptData enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
            [data setJavascriptData:obj forKey:key];
        }];
        return data;
    }
    return nil;
}

@end
