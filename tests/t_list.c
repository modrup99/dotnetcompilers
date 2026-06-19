int printf(int f, ...); int malloc(int n);
struct Node { int val; struct Node *next; };
int main(void){
    struct Node *head = 0; int i;
    for (i = 5; i >= 1; i--) { struct Node *n = (struct Node*)malloc(sizeof(struct Node)); n->val = i; n->next = head; head = n; }
    int sum = 0; struct Node *p = head;
    while (p) { sum += p->val; p = p->next; }
    printf("list sum=%d head=%d (exp 15 1)\n", sum, head->val);
    return 0;
}
