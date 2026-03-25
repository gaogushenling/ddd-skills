---
name: ddd-skills
version: 2.0.0
description: "DDD 六边形架构设计与开发技能包。当你需要设计或实现 DDD 领域驱动设计项目时使用，包括：六边形架构、端口与适配器、领域层设计（Entity/Aggregate/Value Object/Repository/Domain Service）、业务编排层（Case Layer）、触发层（Trigger Layer）、基础设施层（Infrastructure Layer）。触发词：'DDD'、'六边形架构'、'领域驱动设计'、'创建 DDD 项目'、'新建项目'。不要用于简单 CRUD 应用或没有领域复杂度的微服务。@小傅哥"
author: xiaofuge
license: MIT
triggers:
  - "DDD"
  - "六边形架构"
  - "domain-driven design"
  - "领域驱动设计"
  - "ports and adapters"
  - "创建 Entity"
  - "创建聚合根"
  - "创建 DDD 项目"
  - "新建项目"
metadata:
  openclaw:
    emoji: "🏗️"
---

# DDD Hexagonal Architecture

Design and implement software using Domain-Driven Design with Hexagonal Architecture. This skill provides patterns, templates, and best practices for building maintainable domain-centric applications.

## Scripts

### 创建 DDD 项目

当用户需要创建新的 DDD 项目时，**必须先询问用户以下配置参数**，用户确认或给出具体值后再执行 Maven Archetype 命令。

**必须询问的参数：**

| 参数 | 说明 | 默认值（用户不提供时使用） | 示例 |
|------|------|---------------------------|------|
| GroupId | Maven 坐标的 groupId，用于标识组织或公司 | `com.yourcompany` | `cn.bugstack` |
| ArtifactId | 项目模块的唯一标识名称 | `your-project-name` | `order-system` |
| Version | 项目的版本号 | `1.0.0-SNAPSHOT` | `1.0.0-RELEASE` |
| Package | Java 代码的根包名（默认同 groupId） | 同 groupId | `cn.bugstack.order` |

**流程：**
1. 询问用户上述参数（GroupId、ArtifactId 必须询问，Version 和 Package 可选）
2. 用户确认具体值后，执行 Maven Archetype 命令
3. 用户未提供时，使用默认值

> ⚠️ **禁止直接使用默认值创建项目，必须先询问用户确认**

**Maven Archetype 命令模板：**

```bash
mvn archetype:generate \
  -DarchetypeGroupId=io.github.fuzhengwei \
  -DarchetypeArtifactId=ddd-scaffold-lite-jdk17 \
  -DarchetypeVersion=1.3 \
  -DarchetypeRepository=https://maven.xiaofuge.cn/ \
  -DgroupId={用户输入或默认值} \
  -DartifactId={用户输入或默认值} \
  -Dversion={用户输入或默认值} \
  -Dpackage={用户输入或默认值} \
  -B
```

**参数说明：**

| 参数 | 用途 |
|------|------|
| `-DarchetypeGroupId` | 脚手架模板的 groupId |
| `-DarchetypeArtifactId` | 脚手架模板名称 |
| `-DarchetypeVersion` | 脚手架版本 |
| `-DarchetypeRepository` | Maven 私服地址 |
| `-DgroupId` | 项目组织标识 |
| `-DartifactId` | 项目名称 |
| `-Dversion` | 项目版本 |
| `-Dpackage` | Java 根包名 |
| `-B` | 批量模式，不交互 |

## Quick Reference

| Task | Reference |
|------|-----------|
| Architecture overview | [references/architecture.md](references/architecture.md) |
| Entity design | [references/entity.md](references/entity.md) |
| Aggregate design | [references/aggregate.md](references/aggregate.md) |
| Value Object design | [references/value-object.md](references/value-object.md) |
| Repository pattern | [references/repository.md](references/repository.md) |
| Port & Adapter | [references/port-adapter.md](references/port-adapter.md) |
| Domain Service | [references/domain-service.md](references/domain-service.md) |
| Case layer orchestration | [references/case-layer.md](references/case-layer.md) |
| Trigger layer | [references/trigger-layer.md](references/trigger-layer.md) |
| Infrastructure layer | [references/infrastructure-layer.md](references/infrastructure-layer.md) |
| Project structure | [references/project-structure.md](references/project-structure.md) |
| Naming conventions | [references/naming.md](references/naming.md) |
| Docker Images | [references/docker-images.md](references/docker-images.md) |

## Architecture Layers

```
┌─────────────────────────────────────────────────────────────┐
│                     Trigger Layer                            │
│         (HTTP Controller / MQ Listener / Job)               │
└─────────────────────────┬───────────────────────────────────┘
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                       API Layer                              │
│              (DTO / Request / Response)                     │
└─────────────────────────┬───────────────────────────────────┘
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                      Case Layer                              │
│            (Orchestration / Business Flow)                   │
└─────────────────────────┬───────────────────────────────────┘
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                     Domain Layer                             │
│        (Entity / Aggregate / VO / Domain Service)           │
└─────────────────────────┬───────────────────────────────────┘
                          ▲
┌─────────────────────────────────────────────────────────────┐
│                  Infrastructure Layer                        │
│      (Repository Impl / Port Adapter / DAO / PO)            │
└─────────────────────────────────────────────────────────────┘
```

**Dependency Rule**: `Trigger → API → Case → Domain ← Infrastructure`

## Quick Templates

### Entity (Rich Domain Model)

```java
@Data @Builder
public class OrderEntity {
    private Long id;
    private String orderId;
    private OrderStatus status;
    private BigDecimal amount;
    
    // Rich behavior methods
    public boolean canPay() {
        return status == OrderStatus.PENDING;
    }
    
    public void pay() {
        if (!canPay()) throw new BusinessException("Cannot pay");
        this.status = OrderStatus.PAID;
    }
    
    public void validate() {
        if (amount == null || amount.compareTo(BigDecimal.ZERO) <= 0) {
            throw new IllegalArgumentException("Invalid amount");
        }
    }
}
```

### Aggregate

```java
@Data @Builder
public class OrderAggregate {
    private OrderEntity order;           // Root
    private List<OrderItemEntity> items; // Related entities
    private ShippingAddressVO address;   // Value object
    
    public void create() {
        order.validate();
        this.order.setStatus(OrderStatus.CREATED);
    }
    
    public BigDecimal totalAmount() {
        return items.stream()
            .map(OrderItemEntity::getPrice)
            .reduce(BigDecimal.ZERO, BigDecimal::add);
    }
}
```

### Value Object (Immutable)

```java
@Getter
public final class MoneyVO {
    private final BigDecimal amount;
    private final String currency;
    
    private MoneyVO(BigDecimal amount, String currency) {
        this.amount = amount;
        this.currency = currency;
    }
    
    public static MoneyVO of(BigDecimal amount, String currency) {
        return new MoneyVO(amount, currency);
    }
    
    public MoneyVO add(MoneyVO other) {
        return new MoneyVO(amount.add(other.amount), currency);
    }
}
```

### Repository Interface (Domain Layer)

```java
public interface IOrderRepository {
    OrderAggregate findById(Long id);
    OrderAggregate findByOrderId(String orderId);
    void save(OrderAggregate aggregate);
    void update(OrderAggregate aggregate);
}
```

### Repository Implementation (Infrastructure Layer)

```java
@Repository
public class OrderRepositoryImpl implements IOrderRepository {
    @Resource private IOrderDao orderDao;
    
    @Override
    @Transactional
    public void save(OrderAggregate aggregate) {
        OrderPO po = toPO(aggregate);
        orderDao.insert(po);
    }
    
    private OrderPO toPO(OrderAggregate aggregate) {
        // Convert domain object to persistence object
    }
}
```

### Port Interface (Domain Layer)

```java
public interface INotificationPort {
    void sendOrderCreated(OrderCreatedEvent event);
}
```

### Port Adapter (Infrastructure Layer)

```java
@Service
public class NotificationPortImpl implements INotificationPort {
    @Resource private RestTemplate restTemplate;
    
    @Override
    public void sendOrderCreated(OrderCreatedEvent event) {
        restTemplate.postForObject(url, event, Void.class);
    }
}
```

### Controller (Trigger Layer)

```java
@Slf4j
@RestController
@RequestMapping("/api/v1/orders/")
public class OrderController {
    @Resource private IOrderCaseService orderCaseService;
    
    @PostMapping("/create")
    public Response<OrderDTO> create(@RequestBody @Valid CreateOrderRequest request) {
        return orderCaseService.createOrder(request);
    }
}
```

### Domain Service - 完整编码规范

**参考真实工程**：`Documents/project/ddd-demo/group-buy-market`、`Documents/project/ddd-demo/ai-mcp-gateway`

#### 1. 简单领域服务

```java
// 1. 定义服务接口
public interface IOrderDomainService {
    
    /**
     * 查询订单
     */
    OrderAggregate queryById(Long orderId);
    
    /**
     * 创建订单
     */
    OrderAggregate createOrder(OrderCommandEntity command) throws Exception;
}

// 2. 实现服务类（放在子包中）
@Service
@Slf4j
public class OrderDomainServiceImpl implements IOrderDomainService {

    @Resource
    private IOrderRepository orderRepository;

    @Override
    public OrderAggregate queryById(Long orderId) {
        log.info("查询订单 orderId:{}", orderId);
        return orderRepository.findById(orderId);
    }

    @Override
    public OrderAggregate createOrder(OrderCommandEntity command) throws Exception {
        log.info("创建订单 userId:{} activityId:{}", command.getUserId(), command.getActivityId());
        
        // 1. 构建聚合根
        OrderAggregate aggregate = OrderAggregate.builder()
                .orderEntity(OrderEntity.builder()
                        .userId(command.getUserId())
                        .activityId(command.getActivityId())
                        .status(OrderStatus.PENDING)
                        .build())
                .build();
        
        // 2. 执行创建（调用聚合根内部方法）
        aggregate.create();
        
        // 3. 保存
        orderRepository.save(aggregate);
        
        return aggregate;
    }
}
```

#### 2. 策略模式服务

```java
// 1. 定义策略接口
public interface IRefundOrderStrategy {
    void refundOrder(RefundCommandEntity command) throws Exception;
}

// 2. 定义抽象基类（模板方法模式）
@Slf4j
public abstract class AbstractRefundOrderStrategy implements IRefundOrderStrategy {

    @Resource
    protected IOrderRepository orderRepository;

    @Resource
    protected ThreadPoolExecutor threadPoolExecutor;

    /**
     * 通用库存恢复逻辑
     */
    protected void doReverseStock(ReverseStockVO vo) throws Exception {
        log.info("恢复库存 activityId:{} teamId:{}", vo.getActivityId(), vo.getTeamId());
        orderRepository.reverseStock(vo);
    }
}

// 3. 实现具体策略
@Slf4j
@Service("paid2RefundStrategy")
public class Paid2RefundStrategy extends AbstractRefundOrderStrategy {

    @Override
    public void refundOrder(RefundCommandEntity command) throws Exception {
        log.info("退单-已支付 userId:{} teamId:{}", command.getUserId(), command.getTeamId());
        // 已支付退单逻辑：减库存、减完成量、发MQ
        orderRepository.paidRefund(command);
    }
}

@Slf4j
@Service("unpaid2RefundStrategy")
public class Unpaid2RefundStrategy extends AbstractRefundOrderStrategy {

    @Override
    public void refundOrder(RefundCommandEntity command) throws Exception {
        log.info("退单-未支付 userId:{} teamId:{}", command.getUserId(), command.getTeamId());
        // 未支付退单逻辑：只减库存
        orderRepository.unpaidRefund(command);
    }
}
```

#### 3. 责任链模式服务

```java
// 1. 定义过滤器接口
public interface IOrderRuleFilter {
    FilterResult doFilter(FilterCommandEntity command, DynamicContext context);
}

// 2. 实现多个过滤器
@Slf4j
@Service
public class ActivityStatusFilter implements IOrderRuleFilter {
    
    @Override
    public FilterResult doFilter(FilterCommandEntity command, DynamicContext context) {
        log.info("规则校验-活动状态 activityId:{}", command.getActivityId());
        // 校验逻辑
        return FilterResult.builder().passed(true).build();
    }
}

@Slf4j
@Service
public class StockFilter implements IOrderRuleFilter {
    
    @Override
    public FilterResult doFilter(FilterCommandEntity command, DynamicContext context) {
        log.info("规则校验-库存校验 activityId:{}", command.getActivityId());
        // 校验逻辑
        return FilterResult.builder().passed(true).build();
    }
}

// 3. 过滤器工厂
@Slf4j
@Service
public class OrderRuleFilterFactory {

    @Resource
    private ActivityStatusFilter activityStatusFilter;

    @Resource
    private StockFilter stockFilter;

    /**
     * 执行过滤器链
     */
    public FilterResult execute(FilterCommandEntity command) {
        FilterResult result = activityStatusFilter.doFilter(command, null);
        if (!result.isPassed()) return result;
        
        result = stockFilter.doFilter(command, null);
        return result;
    }
}
```

## Core Principles

| Principle | Description |
|-----------|-------------|
| **Dependency Inversion** | Domain defines interfaces, Infrastructure implements |
| **Rich Domain Model** | Entity contains both data and behavior |
| **Aggregate Boundary** | Transaction consistency inside, eventual consistency outside |
| **Anti-Corruption Layer** | Use Port to isolate external systems |
| **Lightweight Trigger** | Trigger layer only routes requests, no business logic |

## When to Use DDD

**Use DDD when:**
- Complex business domain with rich rules
- Need to capture domain knowledge in code
- Long-lived project with evolving requirements
- Team needs shared domain language

**Don't use DDD when:**
- Simple CRUD operations
- Prototype or throwaway code
- Domain logic is trivial
- Team unfamiliar with DDD concepts

## Example Projects

- [group-buy-market](file:///Users/fuzhengwei/Documents/project/ddd-demo/group-buy-market) - E-commerce domain
- [ai-mcp-gateway](file:///Users/fuzhengwei/Documents/project/ddd-demo/ai-mcp-gateway) - API gateway domain
