# Domain Service - 领域服务

## 概述

Domain Service（领域服务）用于封装**跨多个聚合根**的业务逻辑，或**不适合放在单个实体/聚合根上**的操作。

## 何时使用

| 场景 | 是否使用 Domain Service |
|------|------------------------|
| 单个实体/聚合根的职责 | ❌ 放在 Entity/Aggregate 内部 |
| 跨多个聚合根的操作 | ✅ 使用 Domain Service |
| 需要组合多个领域能力 | ✅ 使用 Domain Service |
| 纯计算逻辑 | ✅ 可放在 Domain Service |

## 命名规范

```java
// 接口命名
public interface I{Domain}DomainService {}

// 实现类命名（Infrastructure 层实现）
@Service
public class {Domain}DomainServiceImpl implements I{Domain}DomainService {}
```

## 使用示例

### 1. 跨聚合根操作

当一个业务操作需要操作多个聚合根时，使用 Domain Service：

```java
/**
 * 订单领域服务接口
 */
public interface IOrderDomainService {

    /**
     * 创建订单并扣减库存
     * 需要同时操作 OrderAggregate 和 InventoryAggregate
     */
    OrderAggregate createOrderWithInventory(Long userId, List<OrderItem> items);
    
    /**
     * 订单支付成功后处理
     * 需要更新订单状态 + 通知库存系统 + 发送通知
     */
    void handleOrderPaid(OrderAggregate order);
}

/**
 * 订单领域服务实现
 */
@Service
@Slf4j
public class OrderDomainServiceImpl implements IOrderDomainService {

    @Resource
    private IOrderRepository orderRepository;
    
    @Resource
    private IInventoryRepository inventoryRepository;
    
    @Resource
    private INotificationPort notificationPort;

    @Override
    @Transactional
    public OrderAggregate createOrderWithInventory(Long userId, List<OrderItem> items) {
        log.info("创建订单并扣减库存, userId={}, items={}", userId, items);
        
        // 1. 批量扣减库存（跨聚合根）
        for (OrderItem item : items) {
            InventoryAggregate inventory = inventoryRepository.findByProductId(item.getProductId());
            inventory.deduct(item.getQuantity());
            inventoryRepository.save(inventory);
        }
        
        // 2. 创建订单聚合
        OrderAggregate order = OrderAggregate.builder()
                .orderId(IdUtil.get())
                .userId(userId)
                .items(items)
                .build();
        order.create();
        
        orderRepository.save(order);
        
        return order;
    }

    @Override
    public void handleOrderPaid(OrderAggregate order) {
        log.info("处理订单支付成功, orderId={}", order.getOrderId());
        
        // 1. 更新订单状态（在聚合根内）
        order.paid();
        orderRepository.save(order);
        
        // 2. 发送通知（通过 Port）
        notificationPort.sendOrderPaidNotification(order);
    }
}
```

### 2. 复杂计算逻辑

```java
/**
 * 价格计算领域服务
 */
public interface IPriceCalculationDomainService {

    /**
     * 计算订单最终价格
     * 涉及折扣、优惠券、会员等级等多个维度
     */
    PriceResult calculatePrice(Long userId, List<CartItem> items, String couponCode);
}

/**
 * 价格计算领域服务实现
 */
@Service
@Slf4j
public class PriceCalculationDomainServiceImpl implements IPriceCalculationDomainService {

    @Resource
    private IMemberService memberService;
    
    @Resource
    private ICouponService couponService;
    
    @Resource
    private IProductService productService;

    @Override
    public PriceResult calculatePrice(Long userId, List<CartItem> items, String couponCode) {
        log.info("计算价格, userId={}, items={}, couponCode={}", userId, items, couponCode);
        
        BigDecimal originalPrice = BigDecimal.ZERO;
        
        // 1. 计算原价
        for (CartItem item : items) {
            ProductEntity product = productService.findById(item.getProductId());
            originalPrice = originalPrice.add(
                    product.getPrice().multiply(BigDecimal.valueOf(item.getQuantity()))
            );
        }
        
        // 2. 计算会员折扣
        MemberEntity member = memberService.findById(userId);
        BigDecimal memberDiscount = calculateMemberDiscount(member, originalPrice);
        
        // 3. 计算优惠券折扣
        BigDecimal couponDiscount = BigDecimal.ZERO;
        if (StringUtils.isNotBlank(couponCode)) {
            CouponEntity coupon = couponService.findByCode(couponCode);
            if (coupon.isValid()) {
                couponDiscount = coupon.calculateDiscount(originalPrice);
            }
        }
        
        // 4. 计算最终价格
        BigDecimal finalPrice = originalPrice
                .subtract(memberDiscount)
                .subtract(couponDiscount);
        
        return PriceResult.builder()
                .originalPrice(originalPrice)
                .memberDiscount(memberDiscount)
                .couponDiscount(couponDiscount)
                .finalPrice(finalPrice.max(BigDecimal.ZERO))
                .build();
    }
    
    private BigDecimal calculateMemberDiscount(MemberEntity member, BigDecimal price) {
        MemberLevel level = member.getLevel();
        return price.multiply(BigDecimal.valueOf(level.getDiscountRate()));
    }
}
```

### 3. 状态转换协调

```java
/**
 * 订单状态机领域服务
 */
public interface IOrderStateMachineDomainService {

    /**
     * 执行订单状态转换
     */
    void transition(OrderAggregate order, OrderStatus targetStatus);
}

/**
 * 订单状态机领域服务实现
 */
@Service
@Slf4j
public class OrderStateMachineDomainServiceImpl implements IOrderStateMachineDomainService {

    private static final Map<OrderStatus, Set<OrderStatus>> ALLOWED_TRANSITIONS = 
            ImmutableMap.of(
                    OrderStatus.PENDING, EnumSet.of(OrderStatus.PAID, OrderStatus.CANCELLED),
                    OrderStatus.PAID, EnumSet.of(OrderStatus.SHIPPED, OrderStatus.REFUNDED),
                    OrderStatus.SHIPPED, EnumSet.of(OrderStatus.DELIVERED),
                    OrderStatus.DELIVERED, EnumSet.of(OrderStatus.COMPLETED)
            );

    @Override
    public void transition(OrderAggregate order, OrderStatus targetStatus) {
        OrderStatus currentStatus = order.getStatus();
        
        Set<OrderStatus> allowed = ALLOWED_TRANSITIONS.get(currentStatus);
        if (allowed == null || !allowed.contains(targetStatus)) {
            throw new BusinessException("ORDER_STATUS_TRANSITION_NOT_ALLOWED", 
                    String.format("订单状态 %s 不允许转换为 %s", currentStatus, targetStatus));
        }
        
        log.info("订单状态转换, orderId={}, {} -> {}", 
                order.getOrderId(), currentStatus, targetStatus);
        
        order.changeStatus(targetStatus);
    }
}
```

## 设计原则

### 1. 保持 Domain Service 轻量

```java
// ❌ 错误：Domain Service 过于厚重
@Service
public class OrderDomainServiceImpl {
    
    @Resource
    private OrderRepository orderRepository;
    
    @Resource
    private ProductRepository productRepository;
    
    @Resource
    private UserRepository userRepository;
    
    @Resource
    private RedisTemplate redisTemplate;
    
    // ... 几十个方法
}

// ✅ 正确：按职责拆分多个 Domain Service
public interface IOrderDomainService { /* 订单相关 */ }
public interface IPriceCalculationDomainService { /* 价格计算 */ }
public interface IOrderStateMachineDomainService { /* 状态机 */ }
```

### 2. 依赖方向

```
Domain Service 只依赖：
├── Repository 接口（Domain 层定义）
├── Port 接口（Domain 层定义）
└── 其他 Domain Service 接口

Domain Service 不依赖：
├── Infrastructure 实现
├── DAO 实现
└── 第三方框架
```

### 3. 事务边界

事务通常在 Case 层控制：

```java
@Service
public class OrderCaseServiceImpl implements IOrderCaseService {

    @Resource
    private IOrderDomainService orderDomainService;

    @Override
    @Transactional(rollbackFor = Exception.class)
    public Response<OrderDTO> createOrder(CreateOrderRequest request) {
        // 整个方法在一个事务中
        OrderAggregate order = orderDomainService.createOrderWithInventory(...);
        return Response.ok(OrderDTO.from(order));
    }
}
```

## 与其他组件的关系

```
┌─────────────────────────────────────────────────────────────┐
│                      Case 层                                │
│                   (编排调用)                                 │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                   Domain Service                             │
│                (跨聚合根逻辑)                                 │
└─────────────────────────┬───────────────────────────────────┘
                          │
          ┌───────────────┼───────────────┐
          ▼               ▼               ▼
┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│ Aggregate A │  │ Aggregate B │  │    Port     │
│ (Repository)│  │ (Repository)│  │  (Interface)│
└─────────────┘  └─────────────┘  └─────────────┘
```

## 常见问题

### Q: 什么时候不用 Domain Service？

当操作只涉及单个聚合根时，直接在聚合根内部实现：

```java
// ❌ 不需要 Domain Service
orderDomainService.pay(order, paymentMethod);

// ✅ 直接在聚合根内
order.pay(paymentMethod);
```

### Q: Domain Service 和 Case Service 的区别？

| 维度 | Domain Service | Case Service |
|------|---------------|--------------|
| 位置 | Domain 层 | Case 层 |
| 职责 | 纯业务逻辑 | 编排 + 业务 |
| 依赖 | 只能依赖 Domain 层 | 可依赖 Domain/Case |
| 事务 | 不控制事务 | 控制事务边界 |

### Q: Domain Service 可以依赖其他 Domain Service 吗？

可以，但要谨慎，避免循环依赖：

```java
@Service
public class OrderDomainServiceImpl implements IOrderDomainService {
    
    @Resource
    private IPricingDomainService pricingDomainService; // OK
    
    // 不要反过来让 PricingDomainService 依赖 OrderDomainService
}
```
