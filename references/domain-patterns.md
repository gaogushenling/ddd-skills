# Domain 层核心实现模式

## 目录结构

```
domain/
├── {module}/
│   ├── adapter/
│   │   ├── repository/     # 仓储接口（Domain 定义，Infrastructure 实现）
│   │   └── port/           # 端口接口（外部系统适配）
│   ├── model/
│   │   ├── aggregate/      # 聚合根
│   │   ├── entity/         # 实体（普通实体 + 命令实体）
│   │   └── valobj/         # 值对象（普通 VO + 枚举 VO）
│   └── service/
│       ├── {service}/      # 领域服务
│       │   ├── impl/       # 策略实现
│       │   ├── filter/     # 责任链过滤器
│       │   └── factory/    # 工厂类
```

---

## 一、Repository 仓储模式

### 1.1 接口定义（Domain 层）

```java
/**
 * 仓储接口 - 定义在 Domain 层，由 Infrastructure 层实现
 * 遵循依赖倒置原则：Domain 定义接口，Infrastructure 实现接口
 */
public interface ITradeRepository {

    /**
     * 查询方法
     */
    MarketPayOrderEntity queryMarketPayOrderEntityByOutTradeNo(String userId, String outTradeNo);
    
    GroupBuyProgressVO queryGroupBuyProgress(String teamId);

    /**
     * 聚合操作 - 接收聚合根，返回聚合根或实体
     */
    MarketPayOrderEntity lockMarketPayOrder(GroupBuyOrderAggregate groupBuyOrderAggregate);

    /**
     * 库存操作 - 分布式锁库存
     */
    boolean occupyTeamStock(String teamStockKey, String recoveryTeamStockKey, Integer target, Integer validTime);

    /**
     * 批量查询
     */
    List<NotifyTaskEntity> queryUnExecutedNotifyTaskList();

    /**
     * 状态更新 - 返回影响行数
     */
    int updateNotifyTaskStatusSuccess(NotifyTaskEntity notifyTaskEntity);
}
```

### 1.2 接口实现（Infrastructure 层）

```java
@Slf4j
@Repository
public class TradeRepository implements ITradeRepository {

    @Resource
    private IGroupBuyOrderDao groupBuyOrderDao;
    
    @Resource
    private IRedisService redisService;

    /**
     * 查询结果映射 - PO → Entity
     */
    @Override
    public MarketPayOrderEntity queryMarketPayOrderEntityByOutTradeNo(String userId, String outTradeNo) {
        GroupBuyOrderList groupBuyOrderList = groupBuyOrderListDao.queryGroupBuyOrderRecordByOutTradeNo(
            GroupBuyOrderList.builder().userId(userId).outTradeNo(outTradeNo).build()
        );
        if (null == groupBuyOrderList) return null;

        return MarketPayOrderEntity.builder()
                .orderId(groupBuyOrderList.getOrderId())
                .payPrice(groupBuyOrderList.getPayPrice())
                .tradeOrderStatusEnumVO(TradeOrderStatusEnumVO.valueOf(groupBuyOrderList.getStatus()))
                .build();
    }

    /**
     * 聚合操作 - 使用事务注解
     */
    @Transactional(timeout = 500)
    @Override
    public MarketPayOrderEntity lockMarketPayOrder(GroupBuyOrderAggregate aggregate) {
        // 1. 从聚合中提取数据
        UserEntity user = aggregate.getUserEntity();
        PayActivityEntity activity = aggregate.getPayActivityEntity();
        
        // 2. 构建 PO 对象
        GroupBuyOrder order = GroupBuyOrder.builder()
                .teamId(generateTeamId())
                .activityId(activity.getActivityId())
                .userId(user.getUserId())
                .build();
        
        // 3. 数据库操作
        groupBuyOrderDao.insert(order);
        
        // 4. 返回实体
        return MarketPayOrderEntity.builder()
                .orderId(order.getOrderId())
                .teamId(order.getTeamId())
                .build();
    }
}
```

---

## 二、Domain Service 领域服务

### 2.1 服务接口定义

```java
/**
 * 领域服务接口 - 定义业务能力
 */
public interface ITradeLockOrderService {
    
    /**
     * 查询类操作
     */
    MarketPayOrderEntity queryNoPayMarketPayOrderByOutTradeNo(String userId, String outTradeNo);
    
    /**
     * 业务操作 - 可能抛出业务异常
     */
    MarketPayOrderEntity lockMarketPayOrder(UserEntity user, PayActivityEntity activity, PayDiscountEntity discount) throws Exception;
}
```

### 2.2 服务实现 - 使用责任链

```java
@Slf4j
@Service
public class TradeLockOrderService implements ITradeLockOrderService {

    @Resource
    private ITradeRepository repository;
    
    // 注入责任链 Bean
    @Resource
    private BusinessLinkedList<TradeLockRuleCommandEntity, TradeLockRuleFilterFactory.DynamicContext, TradeLockRuleFilterBackEntity> tradeRuleFilter;

    @Override
    public MarketPayOrderEntity lockMarketPayOrder(UserEntity userEntity, PayActivityEntity activity, PayDiscountEntity discount) throws Exception {
        log.info("锁定营销优惠支付订单:{} activityId:{}", userEntity.getUserId(), activity.getActivityId());

        // 1. 责任链过滤
        TradeLockRuleFilterBackEntity back = tradeRuleFilter.apply(
            TradeLockRuleCommandEntity.builder()
                .activityId(activity.getActivityId())
                .userId(userEntity.getUserId())
                .build(),
            new TradeLockRuleFilterFactory.DynamicContext()
        );

        // 2. 构建聚合对象
        GroupBuyOrderAggregate aggregate = GroupBuyOrderAggregate.builder()
                .userEntity(userEntity)
                .payActivityEntity(activity)
                .payDiscountEntity(discount)
                .userTakeOrderCount(back.getUserTakeOrderCount())
                .build();

        // 3. 调用仓储
        try {
            return repository.lockMarketPayOrder(aggregate);
        } catch (Exception e) {
            // 失败恢复库存
            repository.recoveryTeamStock(back.getRecoveryTeamStockKey(), activity.getValidTime());
            throw e;
        }
    }
}
```

---

## 三、责任链模式

### 3.1 过滤器实现

```java
/**
 * 规则过滤器 - 实现 ILogicHandler 接口
 * 每个过滤器负责一个业务规则的校验
 */
@Slf4j
@Service
public class ActivityUsabilityRuleFilter implements ILogicHandler<TradeLockRuleCommandEntity, TradeLockRuleFilterFactory.DynamicContext, TradeLockRuleFilterBackEntity> {

    @Resource
    private ITradeRepository repository;

    @Override
    public TradeLockRuleFilterBackEntity apply(TradeLockRuleCommandEntity request, TradeLockRuleFilterFactory.DynamicContext context) throws Exception {
        log.info("交易规则过滤-活动可用性校验 activityId:{}", request.getActivityId());

        // 1. 查询活动信息
        GroupBuyActivityEntity activity = repository.queryGroupBuyActivityEntityByActivityId(request.getActivityId());

        // 2. 规则校验 - 不通过则抛异常
        if (!ActivityStatusEnumVO.EFFECTIVE.equals(activity.getStatus())) {
            throw new AppException(ResponseCode.E0101);
        }

        // 3. 时间校验
        Date now = new Date();
        if (now.before(activity.getStartTime()) || now.after(activity.getEndTime())) {
            throw new AppException(ResponseCode.E0102);
        }

        // 4. 写入上下文，传递给下一个过滤器
        context.setGroupBuyActivity(activity);

        // 5. 调用 next 继续执行下一个过滤器
        return next(request, context);
    }
}
```

### 3.2 工厂配置

```java
@Slf4j
@Service
public class TradeLockRuleFilterFactory {

    @Bean("tradeRuleFilter")
    public BusinessLinkedList<TradeLockRuleCommandEntity, DynamicContext, TradeLockRuleFilterBackEntity> tradeRuleFilter(
            ActivityUsabilityRuleFilter activityFilter,
            UserTakeLimitRuleFilter userLimitFilter,
            TeamStockOccupyRuleFilter stockFilter) {

        // 链式组装
        LinkArmory<TradeLockRuleCommandEntity, DynamicContext, TradeLockRuleFilterBackEntity> armory =
                new LinkArmory<>("交易规则过滤链",
                        activityFilter,
                        userLimitFilter,
                        stockFilter);

        return armory.getLogicLink();
    }

    @Data
    @Builder
    @AllArgsConstructor
    @NoArgsConstructor
    public static class DynamicContext {
        private GroupBuyActivityEntity groupBuyActivity;
        private Integer userTakeOrderCount;
    }
}
```

---

## 四、策略模式

### 4.1 策略接口

```java
/**
 * 退款策略接口
 */
public interface IRefundOrderStrategy {
    void refundOrder(TradeRefundOrderEntity entity) throws Exception;
    void reverseStock(TeamRefundSuccess success) throws Exception;
}
```

### 4.2 抽象基类（模板方法）

```java
/**
 * 退款策略抽象基类
 * 定义模板方法，子类实现差异化逻辑
 */
@Slf4j
public abstract class AbstractRefundOrderStrategy implements IRefundOrderStrategy {

    @Resource
    protected ITradeRepository repository;

    @Resource
    protected ThreadPoolExecutor threadPoolExecutor;

    /**
     * 模板方法 - 定义退款流程骨架
     */
    @Override
    public void refundOrder(TradeRefundOrderEntity entity) throws Exception {
        log.info("退单处理 userId:{}", entity.getUserId());
        
        // 1. 子类差异化：执行业务操作
        NotifyTaskEntity task = doRefund(entity);
        
        // 2. 通用逻辑：发送通知
        sendNotify(task);
    }

    /**
     * 子类实现差异化逻辑
     */
    protected abstract NotifyTaskEntity doRefund(TradeRefundOrderEntity entity) throws Exception;

    /**
     * 通用通知逻辑
     */
    protected void sendNotify(NotifyTaskEntity task) {
        if (null != task) {
            threadPoolExecutor.execute(() -> {
                // 发送 MQ 消息
            });
        }
    }

    /**
     * 通用库存恢复
     */
    protected void doReverseStock(TeamRefundSuccess success, String type) throws Exception {
        log.info("退单恢复锁单量 - {}", type);
        String key = generateRecoveryKey(success.getActivityId(), success.getTeamId());
        repository.refund2AddRecovery(key, success.getOrderId());
    }
}
```

### 4.3 具体策略实现

```java
/**
 * 已支付，未成团 - 退款策略
 */
@Slf4j
@Service("paid2RefundStrategy")
public class Paid2RefundStrategy extends AbstractRefundOrderStrategy {

    @Override
    protected NotifyTaskEntity doRefund(TradeRefundOrderEntity entity) throws Exception {
        log.info("退单-已支付，未成团 userId:{}", entity.getUserId());
        return repository.paid2Refund(buildAggregate(entity));
    }
    
    @Override
    public void reverseStock(TeamRefundSuccess success) throws Exception {
        // 具体策略重写库存恢复逻辑
        doReverseStock(success, "已支付，有锁单记录");
    }
}

/**
 * 已支付，已成团 - 退款策略
 */
@Slf4j
@Service("paidTeam2RefundStrategy")
public class PaidTeam2RefundStrategy extends AbstractRefundOrderStrategy {

    @Override
    protected NotifyTaskEntity doRefund(TradeRefundOrderEntity entity) throws Exception {
        log.info("退单-已支付，已成团 userId:{}", entity.getUserId());
        return repository.paidTeam2Refund(buildAggregate(entity));
    }
}
```

---

## 五、聚合根模式

### 5.1 聚合根定义

```java
/**
 * 拼团订单聚合根
 * 聚合多个实体，确保业务一致性边界
 */
@Data
@Builder
@AllArgsConstructor
@NoArgsConstructor
public class GroupBuyOrderAggregate {

    /** 用户实体 */
    private UserEntity userEntity;
    
    /** 支付活动实体 */
    private PayActivityEntity payActivityEntity;
    
    /** 支付优惠实体 */
    private PayDiscountEntity payDiscountEntity;
    
    /** 已参与拼团次数 */
    private Integer userTakeOrderCount;
    
    // 聚合根可以包含业务方法
    public String getBizId() {
        return payActivityEntity.getActivityId() + "_" + userEntity.getUserId() + "_" + (userTakeOrderCount + 1);
    }
}
```

### 5.2 命令实体

```java
/**
 * 命令实体 - 用于接收和处理外部命令
 * 命名规范：XxxCommandEntity
 */
@Data
@Builder
@AllArgsConstructor
@NoArgsConstructor
public class TradeLockRuleCommandEntity {
    
    private String userId;
    private Long activityId;
    private String teamId;
}

/**
 * 过滤返回实体 - 责任链返回结果
 */
@Data
@Builder
@AllArgsConstructor
@NoArgsConstructor
public class TradeLockRuleFilterBackEntity {
    
    private GroupBuyActivityEntity groupBuyActivity;
    private Integer userTakeOrderCount;
    private String recoveryTeamStockKey;
}
```

---

## 六、值对象

### 6.1 普通值对象

```java
/**
 * 通知配置值对象
 * 不可变，值相等
 */
@Getter
@Builder
@AllArgsConstructor
@NoArgsConstructor
public class NotifyConfigVO {
    
    private NotifyTypeEnumVO notifyType;
    private String notifyMQ;
    private String notifyUrl;
}
```

### 6.2 枚举值对象（可包含策略逻辑）

```java
/**
 * 退款类型枚举 - 枚举也是值对象
 * 可以包含策略匹配方法
 */
@Getter
@AllArgsConstructor
public enum RefundTypeEnumVO {

    UNPAID_UNLOCK("unpaid_unlock", "未支付，未成团") {
        @Override
        public boolean matches(GroupBuyOrderEnumVO orderStatus, TradeOrderStatusEnumVO tradeStatus) {
            return GroupBuyOrderEnumVO.PROGRESS.equals(orderStatus) 
                && TradeOrderStatusEnumVO.CREATE.equals(tradeStatus);
        }
    },
    
    PAID_UNFORMED("paid_unformed", "已支付，未成团") {
        @Override
        public boolean matches(GroupBuyOrderEnumVO orderStatus, TradeOrderStatusEnumVO tradeStatus) {
            return GroupBuyOrderEnumVO.PROGRESS.equals(orderStatus) 
                && TradeOrderStatusEnumVO.COMPLETE.equals(tradeStatus);
        }
    };

    private final String code;
    private final String info;

    public abstract boolean matches(GroupBuyOrderEnumVO orderStatus, TradeOrderStatusEnumVO tradeStatus);

    public static RefundTypeEnumVO getType(GroupBuyOrderEnumVO orderStatus, TradeOrderStatusEnumVO tradeStatus) {
        return Arrays.stream(values())
            .filter(v -> v.matches(orderStatus, tradeStatus))
            .findFirst()
            .orElseThrow(() -> new RuntimeException("不支持的退款状态组合"));
    }
}
```

---

## 七、事务管理

### 7.1 仓储层事务

```java
/**
 * 事务超时设置
 */
@Transactional(timeout = 500)
@Override
public MarketPayOrderEntity lockMarketPayOrder(GroupBuyOrderAggregate aggregate) {
    // 操作1
    groupBuyOrderDao.insert(order);
    
    // 操作2
    groupBuyOrderListDao.insert(orderList);
    
    return entity;
}
```

### 7.2 异常回滚

```java
@Override
public MarketPayOrderEntity lockMarketPayOrder(...) throws Exception {
    try {
        return repository.lockMarketPayOrder(aggregate);
    } catch (Exception e) {
        // 失败时恢复库存
        repository.recoveryTeamStock(recoveryKey, validTime);
        throw e;
    }
}
```

### 7.3 并发处理 - 乐观锁

```java
// 更新时检查影响行数
int updateCount = groupBuyOrderDao.updateAddLockCount(teamId);
if (1 != updateCount) {
    // 影响行数不等于1，说明并发冲突
    throw new AppException(ResponseCode.E0005);
}
```

---

## 八、Redis 分布式锁

### 8.1 库存占用

```java
@Override
public boolean occupyTeamStock(String teamStockKey, String recoveryKey, Integer target, Integer validTime) {
    // 1. 获取恢复量
    Long recoveryCount = redisService.getAtomicLong(recoveryKey);
    recoveryCount = null == recoveryCount ? 0 : recoveryCount;

    // 2. 自增并判断
    long occupy = redisService.incr(teamStockKey) + 1;
    if (occupy > target + recoveryCount) {
        redisService.decr(teamStockKey);
        return false;
    }

    // 3. 加锁保护
    String lockKey = teamStockKey + "_" + occupy;
    Boolean lock = redisService.setNx(lockKey, validTime + 60, TimeUnit.MINUTES);

    return lock;
}
```

### 8.2 幂等性处理

```java
@Override
public void refund2AddRecovery(String recoveryKey, String orderId) {
    if (StringUtils.isBlank(recoveryKey)) return;

    // 使用 orderId 作为锁，防止重复操作
    String lockKey = "refund_lock_" + orderId;
    Boolean acquired = redisService.setNx(lockKey, 30 * 24 * 60 * 60 * 1000L, TimeUnit.MINUTES);
    
    if (!acquired) {
        log.warn("订单 {} 恢复库存操作已在进行中", orderId);
        return;
    }

    try {
        redisService.incr(recoveryKey);
    } catch (Exception e) {
        redisService.remove(lockKey);
        throw e;
    }
}
```
