import 'package:shared/shared.dart';

import '../db/app_database.dart';

Budget budgetFromRow(BudgetEntry r) => Budget(
  id: r.id,
  kind: r.kind,
  name: r.name,
  emoji: r.emoji,
  ownerId: r.ownerId,
  createdAt: r.createdAt,
  updatedAt: r.updatedAt,
  updatedBy: r.updatedBy,
  deletedAt: r.deletedAt,
  seq: r.serverSeq,
);

BudgetsCompanion budgetToRow(Budget b) => BudgetEntry(
  id: b.id,
  kind: b.kind,
  name: b.name,
  emoji: b.emoji,
  ownerId: b.ownerId,
  createdAt: b.createdAt,
  updatedAt: b.updatedAt,
  updatedBy: b.updatedBy,
  deletedAt: b.deletedAt,
  serverSeq: b.seq,
).toCompanion(false);

Category categoryFromRow(CategoryEntry r) => Category(
  id: r.id,
  budgetId: r.budgetId,
  name: r.name,
  emoji: r.emoji,
  color: r.color,
  sortOrder: r.sortOrder,
  isSystem: r.isSystem,
  updatedAt: r.updatedAt,
  updatedBy: r.updatedBy,
  deletedAt: r.deletedAt,
  seq: r.serverSeq,
);

CategoriesCompanion categoryToRow(Category c) => CategoryEntry(
  id: c.id,
  budgetId: c.budgetId,
  name: c.name,
  nameSearch: normalizeSearchText(c.name),
  emoji: c.emoji,
  color: c.color,
  sortOrder: c.sortOrder,
  isSystem: c.isSystem,
  updatedAt: c.updatedAt,
  updatedBy: c.updatedBy,
  deletedAt: c.deletedAt,
  serverSeq: c.seq,
).toCompanion(false);

Expense expenseFromRow(ExpenseEntry r) => Expense(
  id: r.id,
  budgetId: r.budgetId,
  categoryId: r.categoryId,
  amount: Money(r.amountKopecks),
  spentOn: r.spentOn,
  comment: r.comment,
  authorId: r.authorId,
  recurringId: r.recurringId,
  recurringMonth: r.recurringMonth,
  createdAt: r.createdAt,
  updatedAt: r.updatedAt,
  updatedBy: r.updatedBy,
  deletedAt: r.deletedAt,
  seq: r.serverSeq,
);

ExpensesCompanion expenseToRow(Expense e) => ExpenseEntry(
  id: e.id,
  budgetId: e.budgetId,
  categoryId: e.categoryId,
  amountKopecks: e.amount.kopecks,
  spentOn: e.spentOn,
  comment: e.comment,
  commentSearch: normalizeSearchText(e.comment),
  authorId: e.authorId,
  recurringId: e.recurringId,
  recurringMonth: e.recurringMonth,
  createdAt: e.createdAt,
  updatedAt: e.updatedAt,
  updatedBy: e.updatedBy,
  deletedAt: e.deletedAt,
  serverSeq: e.seq,
).toCompanion(false);

RecurringRule recurringFromRow(RecurringRuleEntry r) => RecurringRule(
  id: r.id,
  budgetId: r.budgetId,
  categoryId: r.categoryId,
  title: r.title,
  amount: Money(r.amountKopecks),
  dayOfMonth: r.dayOfMonth,
  startMonth: r.startMonth,
  createdAt: r.createdAt,
  updatedAt: r.updatedAt,
  updatedBy: r.updatedBy,
  deletedAt: r.deletedAt,
  seq: r.serverSeq,
);

RecurringRulesCompanion recurringToRow(RecurringRule r) => RecurringRuleEntry(
  id: r.id,
  budgetId: r.budgetId,
  categoryId: r.categoryId,
  title: r.title,
  amountKopecks: r.amount.kopecks,
  dayOfMonth: r.dayOfMonth,
  startMonth: r.startMonth,
  createdAt: r.createdAt,
  updatedAt: r.updatedAt,
  updatedBy: r.updatedBy,
  deletedAt: r.deletedAt,
  serverSeq: r.seq,
).toCompanion(false);

BudgetMember memberFromRow(BudgetMemberEntry r) => BudgetMember(
  budgetId: r.budgetId,
  userId: r.userId,
  role: r.role,
  avatarColor: r.avatarColor,
  joinedAt: r.joinedAt,
  leftAt: r.leftAt,
);

BudgetMembersCompanion memberToRow(BudgetMember m) => BudgetMemberEntry(
  budgetId: m.budgetId,
  userId: m.userId,
  role: m.role,
  avatarColor: m.avatarColor,
  joinedAt: m.joinedAt,
  leftAt: m.leftAt,
).toCompanion(false);

MemberProfile profileFromRow(MemberProfileEntry r) => MemberProfile(
  userId: r.userId,
  displayName: r.displayName,
  avatarColor: r.avatarColor,
  birthday: MonthDay.fromParts(r.birthdayMonth, r.birthdayDay),
);

MemberProfilesCompanion profileToRow(MemberProfile p) => MemberProfileEntry(
  userId: p.userId,
  displayName: p.displayName,
  avatarColor: p.avatarColor,
  birthdayMonth: p.birthday?.month,
  birthdayDay: p.birthday?.day,
).toCompanion(false);
